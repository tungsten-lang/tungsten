"""Bounded C3-symmetry-preserving Metal relay for FlipFleet.

The generated worker has one independent quotient-walk trajectory per Metal
thread.  Both the ordinary two-term flip and the periodic any-axis split are
expanded to their complete cyclic orbit before being XOR-applied, so every
intermediate decomposition remains C3 closed.

Campaign builds compile a dimension-specialized source checked into
``c3_bundle``; the Python generator is retained only for deliberate asset
regeneration and source-level tests. ``poll`` accepts an output only after
exhaustive Tungsten verification and an independent Python exact-tensor plus
C3-closure gate.
"""

from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
from typing import Iterable, TextIO


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
ZOO = HERE.parent / "zoo"
BUNDLE = HERE / "c3_bundle"
BUNDLE_CAPS = {3: 56, 4: 88, 5: 152, 6: 240, 7: 368}
for directory in (str(HERE), str(ZOO)):
    if directory not in sys.path:
        sys.path.insert(0, directory)

from bench_decomp import verify  # noqa: E402
from c3_gpu_worker_gen import generate as _generate_worker  # noqa: E402


RESULT_PREFIX = "C3GPU_RESULT "
MAX_TRAJECTORY_STEPS = 2_000_000_000


class C3GpuRelayError(RuntimeError):
    """A C3 worker failed, or produced a result that did not pass both gates."""


def _validate_size(n: int) -> None:
    if not isinstance(n, int) or not 3 <= n <= 7:
        raise ValueError("C3 GPU relay supports square sizes 3 through 7")


def transpose_mask(mask: int, n: int) -> int:
    """Transpose an n-by-n bit-matrix in row-major bit order."""
    _validate_size(n)
    if mask < 0 or mask >= 1 << (n * n):
        raise ValueError("factor mask is outside the tensor dimension")
    out = 0
    for bit in range(n * n):
        if (mask >> bit) & 1:
            row, col = divmod(bit, n)
            out |= 1 << (col * n + row)
    return out


def c3_image(term: tuple[int, int, int], n: int) -> tuple[int, int, int]:
    """Apply (u,v,w) -> (v,w^T,u^T)."""
    u, v, w = term
    return v, transpose_mask(w, n), transpose_mask(u, n)


def c3_orbit(term: tuple[int, int, int], n: int) -> tuple[tuple[int, int, int], ...]:
    """Return all three cyclic images, retaining repetitions for fixed terms."""
    image1 = c3_image(term, n)
    return term, image1, c3_image(image1, n)


def is_c3_closed(terms: Iterable[tuple[int, int, int]], n: int) -> bool:
    """Check closure of a duplicate-free GF(2) scheme under the C3 action."""
    _validate_size(n)
    sequence = tuple(terms)
    scheme = set(sequence)
    return len(scheme) == len(sequence) and all(c3_image(term, n) in scheme
                                                 for term in scheme)


def xor_toggle_orbit(scheme: set[tuple[int, int, int]],
                     term: tuple[int, int, int], n: int) -> None:
    """Apply the exact sequential ``xor_insert_orbit`` semantics on the CPU."""
    for image in c3_orbit(term, n):
        if 0 in image:
            continue
        if image in scheme:
            scheme.remove(image)
        else:
            scheme.add(image)


def apply_c3_flip(terms: Iterable[tuple[int, int, int]], first: int,
                  second: int, axis: int, n: int) -> tuple[tuple[int, int, int], ...]:
    """Reference implementation of one orbit-preserving quotient flip."""
    sequence = tuple(terms)
    if not 0 <= first < len(sequence) or not 0 <= second < len(sequence):
        raise IndexError("term index is out of range")
    if first == second or axis not in (0, 1, 2):
        raise ValueError("flip needs distinct terms and an axis in 0..2")
    ti, tj = sequence[first], sequence[second]
    if tj in c3_orbit(ti, n):
        raise ValueError("quotient flip cannot pair terms in the same C3 orbit")
    if ti[axis] != tj[axis]:
        raise ValueError("terms do not share the requested factor")
    ui, vi, wi = ti
    uj, vj, wj = tj
    if axis == 0:
        new1 = (ui, vi, wi ^ wj)
        new2 = (ui, vi ^ vj, wj)
    elif axis == 1:
        new1 = (ui, vi, wi ^ wj)
        new2 = (ui ^ uj, vi, wj)
    else:
        new1 = (ui, vi ^ vj, wi)
        new2 = (ui ^ uj, vj, wi)
    scheme = set(sequence)
    for term in (ti, tj, new1, new2):
        xor_toggle_orbit(scheme, term, n)
    return tuple(sorted(scheme))


def apply_c3_split(terms: Iterable[tuple[int, int, int]], target: int,
                   donor: int, axis: int, n: int) -> tuple[tuple[int, int, int], ...]:
    """Reference implementation of the MP any-axis plus transition."""
    sequence = tuple(terms)
    if not 0 <= target < len(sequence) or not 0 <= donor < len(sequence):
        raise IndexError("term index is out of range")
    if axis not in (0, 1, 2):
        raise ValueError("split axis must be in 0..2")
    old = sequence[target]
    prime = sequence[donor][axis]
    second = old[axis] ^ prime
    if prime == 0 or second == 0:
        raise ValueError("split factor must be nonzero and differ from the old factor")
    part1 = list(old)
    part2 = list(old)
    part1[axis] = prime
    part2[axis] = second
    scheme = set(sequence)
    for term in (tuple(part1), tuple(part2), old):
        xor_toggle_orbit(scheme, term, n)
    return tuple(sorted(scheme))


def read_runtime_seed(path: os.PathLike[str] | str) -> list[tuple[int, int, int]]:
    """Read ``R u v w`` records or a bare rank/density-header dump."""
    lines = [line.strip() for line in Path(path).read_text().splitlines() if line.strip()]
    if not lines:
        raise ValueError(f"empty seed: {path}")
    if lines[0].startswith("R "):
        terms: list[tuple[int, int, int]] = []
        for line in lines:
            parts = line.split()
            if len(parts) != 4 or parts[0] != "R":
                raise ValueError(f"invalid R-format seed row: {line!r}")
            terms.append(tuple(int(value) for value in parts[1:]))
        return terms
    header = lines[0].split()
    if len(header) not in (1, 2):
        raise ValueError(f"invalid bare seed header: {lines[0]!r}")
    rank = int(header[0])
    if rank <= 0 or len(lines) != rank + 1:
        raise ValueError(f"seed declares rank {rank}, but contains {len(lines) - 1} rows")
    terms = []
    for line in lines[1:]:
        parts = line.split()
        if len(parts) != 3:
            raise ValueError(f"invalid bare seed row: {line!r}")
        terms.append(tuple(int(value) for value in parts))
    return terms


def exact_terms(terms: Iterable[tuple[int, int, int]], n: int) -> bool:
    """Independently reconstruct the square matrix-multiplication tensor."""
    _validate_size(n)
    sequence = tuple(terms)
    limit = 1 << (n * n)
    return (
        bool(sequence)
        and len(set(sequence)) == len(sequence)
        and all(len(term) == 3 and all(0 < mask < limit for mask in term)
                for term in sequence)
        and verify(sequence, n, n, n)
    )


def exact_c3_terms(terms: Iterable[tuple[int, int, int]], n: int) -> bool:
    sequence = tuple(terms)
    return exact_terms(sequence, n) and is_c3_closed(sequence, n)


def capacity_for_rank(rank: int, band: int = 15, reserve: int = 8) -> int:
    """Size for the full band plus the six-slot orbit-toggle high-water mark."""
    if rank <= 0 or band < 0 or reserve < 6:
        raise ValueError("rank/band/reserve are invalid (reserve must be at least six)")
    needed = rank + band + reserve
    return ((needed + 7) // 8) * 8


def bundle_source(n: int) -> Path:
    """Return the checked-in runtime source for one square tensor."""
    _validate_size(n)
    return BUNDLE / f"c3_{str(n) * 3}.w"


@dataclass(frozen=True)
class C3GpuConfig:
    n: int
    cap: int
    walkers: int = 256
    steps: int = 2_000
    dispatches: int = 1
    band: int = 15
    plus_period: int = 200

    def __post_init__(self) -> None:
        _validate_size(self.n)
        if self.cap <= 6:
            raise ValueError("capacity must leave six temporary orbit slots")
        if not 1 <= self.walkers <= 4096:
            raise ValueError("walkers must be in 1..4096")
        if not 1 <= self.steps <= 1_000_000:
            raise ValueError("steps must be in 1..1000000")
        if not 1 <= self.dispatches <= 64:
            raise ValueError("dispatches must be in 1..64")
        if self.steps * self.dispatches > MAX_TRAJECTORY_STEPS:
            raise ValueError("trajectory step count would overflow the i32 counter")
        if not 0 <= self.band <= self.cap - 6:
            raise ValueError("band must be nonnegative and fit capacity")
        if not 0 <= self.plus_period <= 1_000_000_000:
            raise ValueError("plus period must be in 0..1000000000")

    @property
    def hardware_lanes(self) -> int:
        return self.walkers

    @property
    def threadgroups(self) -> int:
        return (self.walkers + 31) // 32


@dataclass(frozen=True)
class C3GpuResult:
    n: int
    walkers: int
    steps: int
    dispatches: int
    band: int
    plusper: int
    elapsed_ms: int
    attempted: int
    partners: int
    pluses: int
    resets: int
    aggregate_steps_s: int
    rank: int
    density: int
    verify_full: int
    c3_closed: int
    output: str


@dataclass(frozen=True)
class ExactC3Candidate:
    terms: tuple[tuple[int, int, int], ...]
    result: C3GpuResult

    @property
    def rank(self) -> int:
        return len(self.terms)

    @property
    def density(self) -> int:
        return sum(bin(mask).count("1") for term in self.terms for mask in term)


def config_for_seed(n: int, seed_path: os.PathLike[str] | str,
                    **kwargs: int) -> C3GpuConfig:
    terms = read_runtime_seed(seed_path)
    if not exact_c3_terms(terms, n):
        raise ValueError(f"runtime seed is not exact and C3 closed: {seed_path}")
    band = int(kwargs.get("band", 15))
    cap = int(kwargs.pop("cap", capacity_for_rank(len(terms), band)))
    if cap < len(terms) + band + 6:
        raise ValueError("capacity cannot hold the seed band and orbit high-water mark")
    return C3GpuConfig(n=n, cap=cap, **kwargs)


def generate_source(config: C3GpuConfig, metal_ll: os.PathLike[str] | str) -> str:
    return _generate_worker(config.n, config.cap, metal_ll)


def compile_argv(binary: os.PathLike[str] | str,
                 source: os.PathLike[str] | str) -> list[str]:
    return ["bin/tungsten", "-o", os.fspath(binary), os.fspath(source),
            "--release", "--native", "--fast", "--lto"]


def relay_argv(binary: os.PathLike[str] | str, seed: os.PathLike[str] | str,
               output: os.PathLike[str] | str, config: C3GpuConfig) -> list[str]:
    return [
        os.fspath(binary), os.fspath(seed), os.fspath(output),
        str(config.walkers), str(config.steps), str(config.dispatches),
        str(config.band), str(config.plus_period),
    ]


def parse_result(text: str) -> C3GpuResult:
    lines = [line.strip() for line in text.splitlines()
             if line.strip().startswith(RESULT_PREFIX)]
    if not lines:
        raise ValueError("no C3GPU_RESULT line")
    line = lines[-1]
    output_match = re.search(r"\soutput=(.*)$", line)
    if output_match is None:
        raise ValueError("C3GPU_RESULT has no output field")
    output = output_match.group(1)
    fields = dict(re.findall(r"\b([a-z0-9_]+)=(-?\d+)", line[:output_match.start()]))
    names = (
        "n", "walkers", "steps", "dispatches", "band", "plusper",
        "elapsed_ms", "attempted", "partners", "pluses", "resets",
        "aggregate_steps_s", "rank", "density", "verify_full", "c3_closed",
    )
    missing = [name for name in names if name not in fields]
    if missing:
        raise ValueError(f"C3GPU_RESULT missing fields: {', '.join(missing)}")
    return C3GpuResult(**{name: int(fields[name]) for name in names}, output=output)


def load_exact_candidate(output: os.PathLike[str] | str, result: C3GpuResult,
                         n: int) -> ExactC3Candidate:
    if result.verify_full != 1:
        raise C3GpuRelayError("Tungsten exhaustive tensor verification failed")
    if result.c3_closed != 1:
        raise C3GpuRelayError("Tungsten C3-closure verification failed")
    if result.n != n:
        raise C3GpuRelayError(f"result is {result.n}x{result.n}, expected {n}x{n}")
    try:
        terms = tuple(read_runtime_seed(output))
    except (OSError, ValueError) as exc:
        raise C3GpuRelayError(f"cannot read relay output: {exc}") from exc
    density = sum(bin(mask).count("1") for term in terms for mask in term)
    if len(terms) != result.rank or density != result.density:
        raise C3GpuRelayError(
            "result metadata disagrees with output "
            f"(rank {result.rank}/{len(terms)}, density {result.density}/{density})"
        )
    if not exact_terms(terms, n):
        raise C3GpuRelayError("independent Python tensor verification failed")
    if not is_c3_closed(terms, n):
        raise C3GpuRelayError("independent Python C3 verification failed")
    return ExactC3Candidate(terms=terms, result=result)


class C3GpuRelay:
    """Build, launch, poll, and stop one bounded C3 GPU lane family."""

    def __init__(self, run_dir: os.PathLike[str] | str, config: C3GpuConfig,
                 *, tungsten_bin: os.PathLike[str] | str = "bin/tungsten",
                 root: os.PathLike[str] | str = ROOT) -> None:
        self.run_dir = Path(run_dir).resolve()
        self.config = config
        self.root = Path(root).resolve()
        self.tungsten_bin = os.fspath(tungsten_bin)
        self.source = bundle_source(config.n)
        self.metal_ll = self.run_dir / "c3_gpu_relay.ll"
        self.binary = self.run_dir / "c3_gpu_relay"
        self.output = self.run_dir / "c3_gpu_best.txt"
        self.log_path = self.run_dir / "c3_gpu_relay.log"
        self.process: subprocess.Popen[str] | None = None
        self._log: TextIO | None = None
        self._candidate: ExactC3Candidate | None = None
        self._finished = False

    def build(self, timeout: float = 1200) -> None:
        self.run_dir.mkdir(parents=True, exist_ok=True)
        runtime_cap = BUNDLE_CAPS[self.config.n]
        if self.config.cap > runtime_cap:
            raise C3GpuRelayError(
                f"requested capacity {self.config.cap} exceeds checked-in "
                f"{self.config.n}x{self.config.n} C3 capacity {runtime_cap}"
            )
        if not self.source.is_file():
            raise C3GpuRelayError(f"checked-in C3 worker is missing: {self.source}")
        env = dict(os.environ, TUNGSTEN_LL_PATH=os.fspath(self.metal_ll))
        command = compile_argv(self.binary, self.source)
        command[0] = self.tungsten_bin
        completed = subprocess.run(command, cwd=self.root, env=env,
                                   capture_output=True, text=True, timeout=timeout)
        if completed.returncode != 0:
            raise C3GpuRelayError(
                "C3 GPU relay compile failed:\n" + completed.stdout + completed.stderr
            )

    def launch(self, seed: os.PathLike[str] | str,
               output: os.PathLike[str] | str | None = None) -> None:
        if self.process is not None and self.process.poll() is None:
            raise C3GpuRelayError("relay is already running")
        if not self.binary.exists():
            raise C3GpuRelayError("relay is not built")
        terms = read_runtime_seed(seed)
        if len(terms) + self.config.band + 6 > BUNDLE_CAPS[self.config.n]:
            raise ValueError("runtime seed, band, and orbit temporaries exceed capacity")
        if not exact_c3_terms(terms, self.config.n):
            raise ValueError("refusing to launch from a non-exact or non-C3 seed")
        self.output = Path(output).resolve() if output is not None else self.output
        if self.output == Path(seed).resolve():
            raise ValueError("relay output must differ from its runtime seed")
        self.output.parent.mkdir(parents=True, exist_ok=True)
        self.output.unlink(missing_ok=True)
        self._candidate = None
        self._finished = False
        self._log = self.log_path.open("w")
        try:
            self.process = subprocess.Popen(
                relay_argv(self.binary, Path(seed).resolve(), self.output, self.config),
                cwd=self.root, stdout=self._log, stderr=subprocess.STDOUT, text=True,
            )
        except Exception:
            self._log.close()
            self._log = None
            raise

    def poll(self) -> ExactC3Candidate | None:
        if self._candidate is not None:
            return self._candidate
        if self._finished:
            return None
        if self.process is None:
            raise C3GpuRelayError("relay has not been launched")
        returncode = self.process.poll()
        if returncode is None:
            return None
        self._finished = True
        if self._log is not None:
            self._log.close()
            self._log = None
        log = self.log_path.read_text() if self.log_path.exists() else ""
        if returncode != 0:
            raise C3GpuRelayError(f"C3 GPU relay exited {returncode}:\n{log[-4000:]}")
        try:
            result = parse_result(log)
        except ValueError as exc:
            raise C3GpuRelayError(f"malformed C3 GPU log: {exc}") from exc
        expected = (self.config.walkers, self.config.steps, self.config.dispatches,
                    self.config.band, self.config.plus_period)
        actual = (result.walkers, result.steps, result.dispatches,
                  result.band, result.plusper)
        if actual != expected:
            raise C3GpuRelayError("relay result disagrees with launch configuration")
        self._candidate = load_exact_candidate(self.output, result, self.config.n)
        return self._candidate

    def terminate(self, timeout: float = 5) -> None:
        if self.process is not None and self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=timeout)
        if self._log is not None:
            self._log.close()
            self._log = None

    close = terminate


def _parse_tensor(value: str) -> int:
    token = value.lower().replace("×", "x")
    if "x" not in token:
        n = int(token)
    else:
        pieces = token.split("x")
        if len(pieces) != 2 or pieces[0] != pieces[1]:
            raise argparse.ArgumentTypeError("tensor must be square, e.g. 6x6")
        n = int(pieces[0])
    try:
        _validate_size(n)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(str(exc)) from exc
    return n


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tensor", required=True, type=_parse_tensor)
    parser.add_argument("--seed", required=True)
    parser.add_argument("--run-dir", required=True)
    parser.add_argument("--walkers", type=int, default=256)
    parser.add_argument("--steps", type=int, default=2_000)
    parser.add_argument("--dispatches", type=int, default=1)
    parser.add_argument("--band", type=int, default=15)
    parser.add_argument("--plus-period", type=int, default=200)
    parser.add_argument("--cap", type=int)
    parser.add_argument("--output")
    parser.add_argument("--compile-only", action="store_true")
    args = parser.parse_args(argv)
    options = dict(walkers=args.walkers, steps=args.steps,
                   dispatches=args.dispatches, band=args.band,
                   plus_period=args.plus_period)
    if args.cap is not None:
        options["cap"] = args.cap
    config = config_for_seed(args.tensor, args.seed, **options)
    relay = C3GpuRelay(args.run_dir, config)
    relay.build()
    if args.compile_only:
        print(json.dumps({"binary": os.fspath(relay.binary),
                          "config": asdict(config)}, sort_keys=True))
        return 0
    relay.launch(args.seed, args.output)
    try:
        candidate = None
        while candidate is None:
            candidate = relay.poll()
            if candidate is None:
                time.sleep(0.05)
    finally:
        relay.close()
    payload = asdict(candidate.result)
    payload.update(exact=True, c3=True, hardware_lanes=config.hardware_lanes,
                   threadgroups=config.threadgroups)
    print(json.dumps(payload, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
