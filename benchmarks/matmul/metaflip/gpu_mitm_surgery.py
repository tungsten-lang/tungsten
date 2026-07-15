"""Bounded Metal meet-in-the-middle scout for exact local tensor surgery.

The hot path is a generated Tungsten/Metal worker.  For a selected five-term
piece of a GF(2) matrix-multiplication scheme it searches a finite candidate
family for four distinct rank-one terms with the same tensor sum:

1. Metal enumerates every candidate-pair 128-bit linear fingerprint.
2. The Tungsten host builds a collision-preserving open-addressed table.
3. Metal enumerates the other pair and probes for its target complement.
4. Python checks every returned hit against the *complete* tensor signature,
   splices it into the scheme, and reconstructs the full multiplication tensor.

The search is intentionally incomplete: the factor family is the same bounded
selected/XOR/near-neighbor family used by :mod:`mitm_surgery`, and fingerprints
are capped at four equal-key matches per query.  It cannot produce a false
record because no fingerprint hit is trusted.  Tungsten's current ``@gpu``
surface has no device atomic compare-exchange, so the regular pair enumeration
and complementary hash probes run on Metal while hash-table construction runs
on the Tungsten host.

Examples::

    python3 gpu_mitm_surgery.py --selftest
    python3 gpu_mitm_surgery.py --emit-worker 6 --pool 700 --out worker.w
    python3 gpu_mitm_surgery.py scheme.txt 6 --subsets 8 --pool 700 --out hit.txt

``search_scheme_gpu`` and ``GpuMitmWorker.search`` are the launchable APIs for
FlipFleet.  Workers are dimension/pool-specialized and cached in ``workdir``.
"""

from __future__ import annotations

import argparse
import dataclasses
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
from typing import Callable, Iterable, Optional, Sequence, Tuple

from bench_decomp import parse_scheme, verify
from metaflip_proto2 import T, recon
from mitm_surgery import (
    candidate_terms,
    emit_bare,
    guided_subsets,
    tensor_xor,
    terms_in_bounds,
    verify_replacement,
    xor_fingerprint,
)
from sat_surgery import expand


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
TEMPLATE = HERE / "gpu_mitm_worker.w"
MASK64 = (1 << 64) - 1
MASK128 = (1 << 128) - 1
HITS_PER_QUERY = 4
SUPPORTED_DIMS = range(3, 8)


def table_capacity(pool: int) -> int:
    """Return a power-of-two table holding all pairs at load at most 1/2."""
    if pool < 4:
        raise ValueError("GPU MITM candidate pool must be at least 4")
    pairs = pool * (pool - 1) // 2
    capacity = 1
    while capacity < pairs * 2:
        capacity <<= 1
    return capacity


def _quote_w_string(path: str) -> str:
    return path.replace("\\", "\\\\").replace('"', '\\"')


def generate_worker_source(n: int, pool: int, metal_path: os.PathLike) -> str:
    """Specialize the checked-in Tungsten worker for one square dimension."""
    if n not in SUPPORTED_DIMS:
        raise ValueError("GPU MITM supports square dimensions 3 through 7")
    capacity = table_capacity(pool)
    source = TEMPLATE.read_text(encoding="utf-8")
    replacements = {
        "DIM = 5": f"DIM = {n}",
        "POOL_MAX = 700": f"POOL_MAX = {pool}",
        "TABLE_CAP = 524288": f"TABLE_CAP = {capacity}",
        'msl = read_file("benchmarks/matmul/metaflip/gpu_mitm_worker.metal")':
            f'msl = read_file("{_quote_w_string(str(metal_path))}")',
    }
    for old, new in replacements.items():
        if old not in source:
            raise AssertionError(f"worker template marker disappeared: {old}")
        source = source.replace(old, new)
    return source


def _signed64(value: int) -> int:
    value &= MASK64
    return value - (1 << 64) if value & (1 << 63) else value


def split_fingerprint(value: int) -> Tuple[int, int]:
    """Split a 128-bit fingerprint into signed i64 Metal buffer values."""
    value &= MASK128
    return _signed64(value), _signed64(value >> 64)


def join_fingerprint(lo: int, hi: int) -> int:
    """Inverse of :func:`split_fingerprint`, useful in tests and diagnostics."""
    return (lo & MASK64) | ((hi & MASK64) << 64)


def fingerprint_words(value: int) -> Tuple[int, int, int, int]:
    """Return four u32 words, preserving every 128 fingerprint bit.

    The Tungsten host parser represents arbitrary integers correctly, but a
    typed-i64 array assignment currently narrows a boxed BigInt through the
    inline-i48 path.  Four i32 words avoid that compiler boundary and are also
    native on every supported Apple GPU.  Unsigned words also make the host
    and Metal hash shifts identically logical.
    """
    value &= MASK128
    return tuple((value >> shift) & 0xFFFFFFFF for shift in (0, 32, 64, 96))


@dataclasses.dataclass(frozen=True)
class GpuMitmResult:
    replacement: Optional[Tuple[Tuple[int, int, int], ...]]
    candidate_count: int
    fingerprint_hits: int
    exact_hits: int
    metrics: dict
    stdout: str


_HIT_RE = re.compile(r"^GPU_MITM_HIT (\d+) (\d+) (\d+) (\d+)$")


def parse_worker_output(output: str) -> Tuple[list, dict]:
    """Parse the stable line protocol emitted by the Tungsten worker."""
    hits = []
    metrics = {}
    for line in output.splitlines():
        match = _HIT_RE.match(line.strip())
        if match:
            hits.append(tuple(int(value) for value in match.groups()))
        elif line.startswith("GPU_MITM_RESULT "):
            for field in line.split()[1:]:
                key, value = field.split("=", 1)
                metrics[key] = int(value)
    if not metrics:
        raise ValueError("Tungsten GPU MITM worker emitted no result line")
    return hits, metrics


class GpuMitmWorker:
    """Cached dimension-specialized Tungsten/Metal MITM process."""

    def __init__(self, n: int, pool: int = 700, workdir: Optional[os.PathLike] = None,
                 compile_timeout: float = 1200, run_timeout: float = 300):
        if n not in SUPPORTED_DIMS:
            raise ValueError("GPU MITM supports square dimensions 3 through 7")
        table_capacity(pool)  # validates pool too
        if pool > 4096:
            raise ValueError("GPU MITM pool above 4096 is intentionally unsupported")
        self.n = n
        self.pool = pool
        self.workdir = Path(workdir or f"/tmp/tungsten-gpu-mitm-{n}-{pool}").resolve()
        self.compile_timeout = compile_timeout
        self.run_timeout = run_timeout
        stem = f"gpu_mitm_{n}x{n}_p{pool}"
        self.source = self.workdir / f"{stem}.w"
        self.binary = self.workdir / stem
        self.ll = self.workdir / f"{stem}.ll"
        self.metal = self.workdir / f"{stem}.metal"

    def build(self) -> Path:
        """Compile once, with a filesystem lock safe for concurrent fleet lanes."""
        self.workdir.mkdir(parents=True, exist_ok=True)
        expected = generate_worker_source(self.n, self.pool, self.metal)
        lock_path = self.workdir / ".build.lock"
        with lock_path.open("a+") as lock:
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
            current = self.source.read_text(encoding="utf-8") if self.source.exists() else None
            if current == expected and self.binary.exists() and self.metal.exists():
                return self.binary
            temporary = self.source.with_suffix(".w.tmp")
            temporary.write_text(expected, encoding="utf-8")
            os.replace(temporary, self.source)
            env = dict(os.environ, TUNGSTEN_LL_PATH=str(self.ll))
            command = [
                str(ROOT / "bin" / "tungsten"), "-o", str(self.binary),
                str(self.source), "--release", "--native", "--fast", "--lto",
            ]
            result = subprocess.run(
                command, cwd=ROOT, env=env, capture_output=True, text=True,
                timeout=self.compile_timeout,
            )
            if result.returncode:
                raise RuntimeError(
                    "GPU MITM Tungsten compile failed:\n" + result.stdout + result.stderr
                )
            if not self.metal.exists():
                raise RuntimeError("Tungsten compiled without emitting the Metal sidecar")
        return self.binary

    def search(self, target: int, candidates: Sequence[Tuple[int, int, int]],
               ab: Optional[int] = None, bb: Optional[int] = None,
               cb: Optional[int] = None) -> GpuMitmResult:
        """Search for four candidates XORing to ``target`` and verify exactly."""
        ab = self.n * self.n if ab is None else ab
        bb = self.n * self.n if bb is None else bb
        cb = self.n * self.n if cb is None else cb
        candidates = tuple(candidates)
        if not 4 <= len(candidates) <= self.pool:
            raise ValueError(f"candidate count must be in [4,{self.pool}]")
        signatures = tuple(expand(term, ab, bb, cb) for term in candidates)
        fingerprints = tuple(xor_fingerprint(signature) for signature in signatures)
        target_fingerprint = xor_fingerprint(target)
        header = (len(candidates),) + fingerprint_words(target_fingerprint)
        lines = ["%d %d %d %d %d" % header]
        lines.extend("%d %d %d %d" % fingerprint_words(value)
                     for value in fingerprints)
        self.build()
        request_fd, request_name = tempfile.mkstemp(
            prefix="request-", suffix=".txt", dir=self.workdir
        )
        try:
            with os.fdopen(request_fd, "w", encoding="utf-8") as stream:
                stream.write("\n".join(lines) + "\n")
            result = subprocess.run(
                [str(self.binary), request_name], cwd=ROOT, capture_output=True,
                text=True, timeout=self.run_timeout,
            )
            if result.returncode:
                raise RuntimeError(
                    f"GPU MITM worker failed ({result.returncode}):\n" +
                    result.stdout + result.stderr
                )
            hits, metrics = parse_worker_output(result.stdout)
        finally:
            try:
                os.unlink(request_name)
            except FileNotFoundError:
                pass

        exact_hits = 0
        replacement = None
        seen = set()
        for indices in hits:
            if any(index < 0 or index >= len(candidates) for index in indices):
                raise ValueError("GPU MITM worker returned an out-of-range index")
            if len(set(indices)) != 4:
                raise ValueError("GPU MITM worker returned repeated candidate indices")
            key = tuple(sorted(indices))
            if key in seen:
                continue
            seen.add(key)
            # Complete signatures, not fingerprints, are the acceptance gate.
            value = 0
            for index in key:
                value ^= signatures[index]
            if value == target:
                exact_hits += 1
                if replacement is None:
                    replacement = tuple(candidates[index] for index in key)
        return GpuMitmResult(
            replacement=replacement,
            candidate_count=len(candidates),
            fingerprint_hits=len(hits),
            exact_hits=exact_hits,
            metrics=metrics,
            stdout=result.stdout,
        )


def search_scheme_gpu(path: os.PathLike, n: int, subset_count: int = 8,
                      pool: int = 700, nearby: int = 2,
                      explicit_subset: Optional[Sequence[int]] = None,
                      workdir: Optional[os.PathLike] = None,
                      log: Callable[[str], None] = print,
                      worker_pool: Optional[int] = None,
                      subset_offset: int = 0):
    """Try bounded exact 5->4 surgeries; return a verified reduced scheme."""
    if n not in SUPPORTED_DIMS:
        raise ValueError("GPU MITM supports square dimensions 3 through 7")
    if subset_offset < 0:
        raise ValueError("GPU MITM subset offset must be nonnegative")
    raw_terms = parse_scheme(str(path))
    terms = sorted(set(raw_terms))
    bits = n * n
    if len(terms) != len(raw_terms) or not terms_in_bounds(terms, bits, bits, bits):
        raise ValueError("input scheme has duplicate, zero, or out-of-range factors")
    if not verify(terms, n, n, n):
        raise ValueError("input scheme is not exact")
    if explicit_subset is not None:
        subset = tuple(explicit_subset)
        if len(subset) != 5 or len(set(subset)) != 5:
            raise ValueError("explicit GPU MITM subset must contain five distinct indices")
        if any(index < 0 or index >= len(terms) for index in subset):
            raise ValueError("explicit GPU MITM subset index is out of range")
        subsets = [subset]
    else:
        # Fleet restarts advance through the deterministic guided beam instead
        # of spending every bounded launch on the same first few five-sets.
        subsets = guided_subsets(terms, 5, subset_count + subset_offset)
        subsets = subsets[subset_offset:subset_offset + subset_count]
    worker_pool = pool if worker_pool is None else worker_pool
    if worker_pool < pool:
        raise ValueError("worker_pool cannot be smaller than the candidate pool")
    worker = GpuMitmWorker(n, pool=worker_pool, workdir=workdir)
    started = time.monotonic()
    for ordinal, subset in enumerate(subsets, 1):
        candidates = candidate_terms(
            terms, subset, bits, bits, bits, limit=pool, nearby=nearby
        )
        target = tensor_xor((terms[index] for index in subset), bits, bits, bits)
        result = worker.search(target, candidates, bits, bits, bits)
        if result.replacement is not None:
            reduced = verify_replacement(terms, subset, result.replacement, n, n, n)
            if reduced is not None:
                log(
                    f"GPU MITM HIT subset={subset} pool={len(candidates)} "
                    f"rank {len(terms)} -> {len(reduced)} exact_hits={result.exact_hits}"
                )
                return reduced
        log(
            f"GPU MITM subset {ordinal}/{len(subsets)} {subset} "
            f"pool={len(candidates)} fingerprint_hits={result.fingerprint_hits} miss"
        )
    log(
        f"GPU MITM MISS tested={len(subsets)} "
        f"elapsed={time.monotonic() - started:.3f}s"
    )
    return None


@dataclasses.dataclass(frozen=True)
class GpuMitmBudgetPlan:
    """A strict mapping from fleet budget to bounded Metal dispatch work."""

    logical_threads: int
    subsets: int
    pool: int
    dispatched_threads: int


def plan_lane_budget(logical_threads: int, max_pool: int = 700,
                     target_subsets: int = 4) -> GpuMitmBudgetPlan:
    """Split logical Metal invocations between candidate depth and subsets.

    One subset dispatches ``pool**2`` threads (the lower triangle exits
    immediately).  Four subsets is the default diversity target.  Except for
    the irreducible four-candidate/16-thread minimum, the returned dispatch
    count never exceeds ``logical_threads``.
    """
    if logical_threads <= 0:
        raise ValueError("GPU MITM logical thread budget must be positive")
    if max_pool < 4:
        raise ValueError("GPU MITM max_pool must be at least 4")
    if target_subsets <= 0:
        raise ValueError("GPU MITM target_subsets must be positive")
    minimum = 4 * 4
    if logical_threads < minimum:
        return GpuMitmBudgetPlan(logical_threads, 1, 4, minimum)
    subsets = min(target_subsets, max(1, logical_threads // minimum))
    pool = min(max_pool, math.isqrt(logical_threads // subsets))
    pool = max(4, pool)
    # If max_pool caps depth, spend remaining budget on more independently
    # guided subsets instead of silently leaving the role idle.
    subsets = min(
        max(target_subsets, subsets),
        max(1, logical_threads // (pool * pool)),
    )
    return GpuMitmBudgetPlan(
        logical_threads=logical_threads,
        subsets=subsets,
        pool=pool,
        dispatched_threads=subsets * pool * pool,
    )


class GpuMitmFleetAdapter:
    """Asynchronous bounded adapter with FlipFleet-style process lifecycle.

    ``lane_budget`` is a budget of logical kernel invocations, not physical
    Apple execution lanes.  This makes accounting deterministic across GPU
    generations: a subset with pool P consumes exactly P^2 dispatch threads.
    The adapter owns at most one child at a time and only leaves ``output``
    behind when the child has independently verified a strictly lower-rank
    exact scheme.
    """

    def __init__(self, n: int, max_pool: int = 700,
                 workdir: Optional[os.PathLike] = None,
                 target_subsets: int = 4):
        if n not in SUPPORTED_DIMS:
            raise ValueError("GPU MITM supports square dimensions 3 through 7")
        table_capacity(max_pool)
        self.n = n
        self.max_pool = max_pool
        self.workdir = Path(
            workdir or f"/tmp/tungsten-gpu-mitm-fleet-{n}-{max_pool}"
        ).resolve()
        self.target_subsets = target_subsets
        self.process = None
        self.plan = None
        self.seed = None
        self.output = None
        self.log_path = None
        self._log_stream = None
        self._seed_key = None
        self._subset_cursor = 0
        self.subset_offset = 0

    def build(self) -> Path:
        return GpuMitmWorker(
            self.n, pool=self.max_pool, workdir=self.workdir
        ).build()

    def launch(self, seed: os.PathLike, output: os.PathLike,
               lane_budget: int, nearby: int = 2):
        if self.process is not None and self.process.poll() is None:
            raise RuntimeError("GPU MITM fleet adapter is already running")
        self.terminate()
        self.build()
        self.plan = plan_lane_budget(
            lane_budget, self.max_pool, self.target_subsets
        )
        self.seed = Path(seed).resolve()
        seed_key = (self.seed, hashlib.sha256(self.seed.read_bytes()).digest())
        if seed_key != self._seed_key:
            self._seed_key = seed_key
            self._subset_cursor = 0
        subset_offset = self._subset_cursor % 256
        self.subset_offset = subset_offset
        self._subset_cursor += self.plan.subsets
        self.output = Path(output).resolve()
        self.output.parent.mkdir(parents=True, exist_ok=True)
        self.output.unlink(missing_ok=True)
        self.workdir.mkdir(parents=True, exist_ok=True)
        self.log_path = self.workdir / (
            f"fleet-{os.getpid()}-{time.monotonic_ns()}.log"
        )
        self._log_stream = self.log_path.open("w", encoding="utf-8")
        command = [
            sys.executable, str(Path(__file__).resolve()), str(self.seed),
            str(self.n), "--subsets", str(self.plan.subsets),
            "--subset-offset", str(subset_offset),
            "--pool", str(self.plan.pool),
            "--worker-pool", str(self.max_pool),
            "--nearby", str(nearby), "--workdir", str(self.workdir),
            "--out", str(self.output), "--json",
        ]
        self.process = subprocess.Popen(
            command, cwd=ROOT, stdout=self._log_stream,
            stderr=subprocess.STDOUT, text=True,
        )
        return self.plan

    def poll(self) -> dict:
        if self.process is None:
            return {"running": False, "returncode": None, "hit": False}
        returncode = self.process.poll()
        running = returncode is None
        if not running and self._log_stream is not None:
            self._log_stream.flush()
            self._log_stream.close()
            self._log_stream = None
        payload = None
        if not running and self.log_path is not None and self.log_path.exists():
            for line in reversed(self.log_path.read_text(encoding="utf-8").splitlines()):
                if line.startswith("{"):
                    try:
                        payload = json.loads(line)
                    except json.JSONDecodeError:
                        payload = None
                    break
        return {
            "running": running,
            "returncode": returncode,
            "hit": bool(self.output and self.output.exists() and
                        self.output.stat().st_size),
            "output": str(self.output) if self.output is not None else None,
            "log": str(self.log_path) if self.log_path is not None else None,
            "plan": dataclasses.asdict(self.plan) if self.plan else None,
            "subset_offset": self.subset_offset,
            "result": payload,
        }

    def terminate(self, timeout: float = 5) -> None:
        process = self.process
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=timeout)
        if self._log_stream is not None:
            self._log_stream.close()
            self._log_stream = None
        self.process = None

    close = terminate


def selftest_cpu() -> None:
    """Exercise the exact acceptance gate without requiring a Metal device."""
    candidates = (
        (1, 1, 1), (2, 2, 2), (4, 4, 4), (8, 8, 8),
        (3, 1, 1), (1, 3, 1),
    )
    target = tensor_xor(candidates[:4], 4, 4, 4)
    fingerprints = [xor_fingerprint(expand(term, 4, 4, 4)) for term in candidates]
    fp_target = xor_fingerprint(target)
    assert fingerprints[0] ^ fingerprints[1] ^ fingerprints[2] ^ fingerprints[3] == fp_target
    assert join_fingerprint(*split_fingerprint(fp_target)) == fp_target
    print("gpu MITM CPU selftest ok")


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("scheme", nargs="?")
    parser.add_argument("n", nargs="?", type=int)
    parser.add_argument("--subsets", type=int, default=8)
    parser.add_argument("--subset-offset", type=int, default=0)
    parser.add_argument("--pool", type=int, default=700)
    parser.add_argument(
        "--worker-pool", type=int,
        help="compile/cache this capacity while searching only --pool candidates",
    )
    parser.add_argument("--nearby", type=int, default=2)
    parser.add_argument("--subset", help="five comma-separated term indices")
    parser.add_argument("--workdir")
    parser.add_argument("--out")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--build-only", action="store_true")
    parser.add_argument("--emit-worker", type=int, metavar="N")
    args = parser.parse_args(argv)
    if args.selftest:
        selftest_cpu()
        return 0
    if args.emit_worker is not None:
        if not args.out:
            parser.error("--emit-worker requires --out")
        metal = str(Path(args.out).with_suffix(".metal").resolve())
        Path(args.out).write_text(
            generate_worker_source(args.emit_worker, args.pool, metal), encoding="utf-8"
        )
        return 0
    if args.build_only:
        if args.n is None:
            parser.error("--build-only requires N")
        binary = GpuMitmWorker(args.n, args.pool, args.workdir).build()
        print(binary)
        return 0
    if args.scheme is None or args.n is None:
        parser.error("scheme and N are required")
    explicit = None
    if args.subset:
        explicit = tuple(int(value) for value in args.subset.split(","))
    messages = []
    result = search_scheme_gpu(
        args.scheme, args.n, args.subsets, args.pool, args.nearby, explicit,
        args.workdir, log=messages.append if args.json else print,
        worker_pool=args.worker_pool,
        subset_offset=args.subset_offset,
    )
    if result is not None and args.out:
        emit_bare(result, args.out)
    if args.json:
        print(json.dumps({
            "hit": result is not None,
            "rank": len(result) if result is not None else None,
            "output": args.out if result is not None and args.out else None,
            "log": messages,
        }, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
