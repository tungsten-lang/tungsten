"""Reusable launcher for the cooperative SIMD-group Metal flip walker.

The cooperative walker is deliberately different from FlipFleet's ordinary
GPU engine: one complete decomposition is owned by one 32-lane SIMD-group.
This module turns the standalone benchmark into a small coordinator-facing
API without coupling it to FlipFleet's scheduling policy.

Typical use::

    config = config_for_seed(6, seed_path, groups=128, steps=50_000)
    relay = CooperativeSimdRelay(run_dir, config)
    relay.build()
    relay.launch(seed_path)
    while (candidate := relay.poll()) is None:
        time.sleep(0.1)

``poll`` returns only after both the Tungsten host's exhaustive check and an
independent Python tensor reconstruction have accepted the result.  Sizes
3x3 through 5x5 use the measured-faster cooperative scan; 6x6 and 7x7 use the
maintained shared-memory hash chains.
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
from typing import TextIO


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
ZOO = HERE.parent / "zoo"
for directory in (str(HERE), str(ZOO)):
    if directory not in sys.path:
        sys.path.insert(0, directory)

from bench_decomp import verify  # noqa: E402
from gpu_simdgroup_gen import generate as _generate_simdgroup  # noqa: E402


SCAN = "scan"
HASH = "hash"
AUTO = "auto"
MODE_NUMBER = {SCAN: 0, HASH: 1}
RESULT_PREFIX = "SIMDGROUP_RESULT "
MAX_TRAJECTORY_STEPS = 2_000_000_000
MAX_THREADGROUP_MEMORY = 32_768
METAL_EMITTER_SHARED_OVERHEAD = 32 * 4 * 2


class SimdgroupRelayError(RuntimeError):
    """The generated relay failed, or produced a non-exact result."""


def partner_mode(n: int) -> str:
    """Return the measured-faster partner lookup for a square tensor."""
    _validate_size(n)
    return SCAN if n <= 5 else HASH


def capacity_for_rank(rank: int, margin: int = 4, reserve: int = 12) -> int:
    """Choose a SIMD-friendly capacity with room for temporary rank escapes.

    Twelve spare slots reproduces the useful checked-in capacities (112 for a
    rank-93 seed, 168 for rank 153) after rounding.  A larger requested margin
    always wins.
    """
    if rank <= 0:
        raise ValueError("rank must be positive")
    if margin < 0 or reserve < 0:
        raise ValueError("margin and reserve must be nonnegative")
    needed = rank + max(margin, reserve)
    return ((needed + 7) // 8) * 8


def shared_memory_bytes(n: int, cap: int) -> int:
    """Return total static threadgroup memory, including emitter scratch."""
    _validate_size(n)
    if cap <= 0:
        raise ValueError("cap must be positive")
    mask_bytes = 8 if n * n > 30 else 4
    hash_size = 512 if mask_bytes == 8 else 256
    scheme = 3 * cap * mask_bytes + 6 * mask_bytes + 4 * (3 * hash_size + 3 * cap)
    return scheme + METAL_EMITTER_SHARED_OVERHEAD


@dataclass(frozen=True)
class SimdgroupConfig:
    """Compile- and launch-time settings for one cooperative lane family."""

    n: int
    cap: int
    groups: int = 128
    steps: int = 20_000
    dispatches: int = 1
    margin: int = 4
    mode: str = AUTO

    def __post_init__(self) -> None:
        _validate_size(self.n)
        if self.cap <= 0:
            raise ValueError("cap must be positive")
        if self.groups <= 0:
            raise ValueError("groups must be positive")
        if self.steps <= 0 or self.dispatches <= 0:
            raise ValueError("steps and dispatches must be positive")
        if self.margin < 0:
            raise ValueError("margin must be nonnegative")
        if self.mode not in (AUTO, SCAN, HASH):
            raise ValueError("mode must be auto, scan, or hash")
        if self.steps * self.dispatches > MAX_TRAJECTORY_STEPS:
            raise ValueError("per-trajectory step count would overflow the i32 counter")
        shared = shared_memory_bytes(self.n, self.cap)
        if shared > MAX_THREADGROUP_MEMORY:
            raise ValueError(
                f"capacity needs {shared} bytes of threadgroup memory; "
                f"Metal limit is {MAX_THREADGROUP_MEMORY}"
            )

    @property
    def selected_mode(self) -> str:
        return partner_mode(self.n) if self.mode == AUTO else self.mode

    @property
    def mode_number(self) -> int:
        return MODE_NUMBER[self.selected_mode]

    @property
    def hardware_lanes(self) -> int:
        return self.groups * 32


@dataclass(frozen=True)
class SimdgroupResult:
    mode: int
    n: int
    groups: int
    steps: int
    dispatches: int
    elapsed_ms: int
    attempted: int
    partners: int
    aggregate_steps_s: int
    trajectory_steps_s: int
    rank: int
    density: int
    verify_full: int
    output: str


@dataclass(frozen=True)
class ExactCandidate:
    """A result accepted by both exhaustive verification implementations."""

    terms: tuple[tuple[int, int, int], ...]
    result: SimdgroupResult

    @property
    def rank(self) -> int:
        return len(self.terms)

    @property
    def density(self) -> int:
        return sum(bin(mask).count("1") for term in self.terms for mask in term)


def _validate_size(n: int) -> None:
    if not isinstance(n, int) or not 3 <= n <= 7:
        raise ValueError("cooperative SIMD relay supports square sizes 3 through 7")


def read_runtime_seed(path: os.PathLike[str] | str) -> list[tuple[int, int, int]]:
    """Read either ``R u v w`` records or FlipFleet's bare rank-header dump."""
    lines = [line.strip() for line in Path(path).read_text().splitlines() if line.strip()]
    if not lines:
        raise ValueError(f"empty seed: {path}")
    if lines[0].startswith("R "):
        terms = []
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
    rows = lines[1:]
    if rank <= 0 or len(rows) != rank:
        raise ValueError(f"seed declares rank {rank}, but contains {len(rows)} rows")
    terms = []
    for line in rows:
        parts = line.split()
        if len(parts) != 3:
            raise ValueError(f"invalid bare seed row: {line!r}")
        terms.append(tuple(int(value) for value in parts))
    return terms


def exact_terms(terms: list[tuple[int, int, int]] | tuple[tuple[int, int, int], ...],
                n: int) -> bool:
    """Apply FlipFleet-compatible structural checks and reconstruct the tensor."""
    _validate_size(n)
    limit = 1 << (n * n)
    return (
        bool(terms)
        and len(set(terms)) == len(terms)
        and all(len(term) == 3 and all(0 < mask < limit for mask in term)
                for term in terms)
        and verify(terms, n, n, n)
    )


def config_for_seed(n: int, seed_path: os.PathLike[str] | str, **kwargs) -> SimdgroupConfig:
    """Build a capacity-safe config from an exact runtime seed."""
    terms = read_runtime_seed(seed_path)
    if not exact_terms(terms, n):
        raise ValueError(f"runtime seed is not an exact {n}x{n} scheme: {seed_path}")
    margin = int(kwargs.get("margin", 4))
    cap = kwargs.pop("cap", capacity_for_rank(len(terms), margin))
    if cap < len(terms) + margin:
        raise ValueError("cap must accommodate the runtime seed plus its rank margin")
    return SimdgroupConfig(n=n, cap=cap, **kwargs)


def generate_source(config: SimdgroupConfig, metal_ll: os.PathLike[str] | str) -> str:
    """Specialize the checked-in Tungsten walker for a coordinator run."""
    return _generate_simdgroup(config.n, config.cap, os.fspath(metal_ll))


def compile_argv(binary: os.PathLike[str] | str,
                 source: os.PathLike[str] | str) -> list[str]:
    """Return the optimized Tungsten compiler command used by the adapter."""
    return [
        "bin/tungsten", "-o", os.fspath(binary), os.fspath(source),
        "--release", "--native", "--fast", "--lto",
    ]


def relay_argv(binary: os.PathLike[str] | str,
               seed: os.PathLike[str] | str,
               output: os.PathLike[str] | str,
               config: SimdgroupConfig) -> list[str]:
    """Return the standalone host's positional command line."""
    return [
        os.fspath(binary), os.fspath(seed), os.fspath(output),
        str(config.groups), str(config.steps), str(config.dispatches),
        str(config.margin), str(config.mode_number),
    ]


def parse_result(text: str) -> SimdgroupResult:
    """Parse the last machine-readable result line from a relay log."""
    lines = [line.strip() for line in text.splitlines()
             if line.strip().startswith(RESULT_PREFIX)]
    if not lines:
        raise ValueError("no SIMDGROUP_RESULT line")
    line = lines[-1]
    output_match = re.search(r"\soutput=(.*)$", line)
    if output_match is None:
        raise ValueError("SIMDGROUP_RESULT has no output field")
    output = output_match.group(1)
    fields = dict(re.findall(r"\b([a-z_]+)=(-?\d+)", line[:output_match.start()]))
    names = (
        "mode", "n", "groups", "steps", "dispatches", "elapsed_ms",
        "attempted", "partners", "aggregate_steps_s", "trajectory_steps_s",
        "rank", "density", "verify_full",
    )
    missing = [name for name in names if name not in fields]
    if missing:
        raise ValueError(f"SIMDGROUP_RESULT missing fields: {', '.join(missing)}")
    values = {name: int(fields[name]) for name in names}
    return SimdgroupResult(**values, output=output)


def load_exact_candidate(output: os.PathLike[str] | str,
                         result: SimdgroupResult, n: int) -> ExactCandidate:
    """Independently exact-check an output described by ``result``."""
    if result.verify_full != 1:
        raise SimdgroupRelayError("Tungsten exhaustive verification failed")
    if result.n != n:
        raise SimdgroupRelayError(f"result is {result.n}x{result.n}, expected {n}x{n}")
    try:
        terms = tuple(read_runtime_seed(output))
    except (OSError, ValueError) as exc:
        raise SimdgroupRelayError(f"cannot read relay output: {exc}") from exc
    density = sum(bin(mask).count("1") for term in terms for mask in term)
    if len(terms) != result.rank or density != result.density:
        raise SimdgroupRelayError(
            "result metadata disagrees with output "
            f"(rank {result.rank}/{len(terms)}, density {result.density}/{density})"
        )
    if not exact_terms(terms, n):
        raise SimdgroupRelayError("independent Python tensor verification failed")
    return ExactCandidate(terms=terms, result=result)


class CooperativeSimdRelay:
    """Build, launch, poll, and stop one bounded cooperative GPU relay."""

    def __init__(self, run_dir: os.PathLike[str] | str, config: SimdgroupConfig,
                 *, tungsten_bin: os.PathLike[str] | str = "bin/tungsten",
                 root: os.PathLike[str] | str = ROOT) -> None:
        self.run_dir = Path(run_dir).resolve()
        self.config = config
        self.root = Path(root).resolve()
        self.tungsten_bin = os.fspath(tungsten_bin)
        self.source = self.run_dir / "simdgroup_relay.w"
        self.metal_ll = self.run_dir / "simdgroup_relay.ll"
        self.binary = self.run_dir / "simdgroup_relay"
        self.output = self.run_dir / "simdgroup_best.txt"
        self.log_path = self.run_dir / "simdgroup_relay.log"
        self.process: subprocess.Popen[str] | None = None
        self._log: TextIO | None = None
        self._candidate: ExactCandidate | None = None
        self._finished = False

    def build(self, timeout: float = 1200) -> None:
        self.run_dir.mkdir(parents=True, exist_ok=True)
        self.source.write_text(generate_source(self.config, self.metal_ll))
        env = dict(os.environ, TUNGSTEN_LL_PATH=os.fspath(self.metal_ll))
        command = compile_argv(self.binary, self.source)
        command[0] = self.tungsten_bin
        completed = subprocess.run(
            command, cwd=self.root, env=env, capture_output=True, text=True,
            timeout=timeout,
        )
        if completed.returncode != 0:
            raise SimdgroupRelayError(
                "cooperative SIMD relay compile failed:\n" +
                completed.stdout + completed.stderr
            )

    def launch(self, seed: os.PathLike[str] | str,
               output: os.PathLike[str] | str | None = None) -> None:
        if self.process is not None and self.process.poll() is None:
            raise SimdgroupRelayError("relay is already running")
        if not self.binary.exists():
            raise SimdgroupRelayError("relay is not built")
        terms = read_runtime_seed(seed)
        if len(terms) + self.config.margin > self.config.cap:
            raise ValueError("runtime seed and margin exceed compiled capacity")
        if not exact_terms(terms, self.config.n):
            raise ValueError("refusing to launch from a non-exact runtime seed")
        self.output = Path(output).resolve() if output is not None else self.output
        if self.output == Path(seed).resolve():
            raise ValueError("relay output must differ from its runtime seed")
        self.output.parent.mkdir(parents=True, exist_ok=True)
        self.output.unlink(missing_ok=True)
        self._candidate = None
        self._finished = False
        self._log = self.log_path.open("w")
        command = relay_argv(
            self.binary, Path(seed).resolve(), self.output, self.config,
        )
        try:
            self.process = subprocess.Popen(
                command, cwd=self.root, stdout=self._log,
                stderr=subprocess.STDOUT, text=True,
            )
        except Exception:
            self._log.close()
            self._log = None
            raise

    def poll(self) -> ExactCandidate | None:
        """Return an independently exact candidate once the bounded run exits."""
        if self._candidate is not None:
            return self._candidate
        if self._finished:
            return None
        if self.process is None:
            raise SimdgroupRelayError("relay has not been launched")
        returncode = self.process.poll()
        if returncode is None:
            return None
        self._finished = True
        if self._log is not None:
            self._log.close()
            self._log = None
        log = self.log_path.read_text() if self.log_path.exists() else ""
        if returncode != 0:
            raise SimdgroupRelayError(
                f"cooperative SIMD relay exited {returncode}:\n{log[-4000:]}"
            )
        try:
            result = parse_result(log)
        except ValueError as exc:
            raise SimdgroupRelayError(f"malformed cooperative relay log: {exc}") from exc
        if result.mode != self.config.mode_number:
            raise SimdgroupRelayError("relay ran a different lookup mode than requested")
        if (result.groups, result.steps, result.dispatches) != (
                self.config.groups, self.config.steps, self.config.dispatches):
            raise SimdgroupRelayError("relay result disagrees with launch configuration")
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
    parser.add_argument("--groups", type=int, default=128)
    parser.add_argument("--steps", type=int, default=20_000)
    parser.add_argument("--dispatches", type=int, default=1)
    parser.add_argument("--margin", type=int, default=4)
    parser.add_argument("--mode", choices=(AUTO, SCAN, HASH), default=AUTO)
    parser.add_argument("--cap", type=int)
    parser.add_argument("--output")
    parser.add_argument("--compile-only", action="store_true")
    args = parser.parse_args(argv)
    options = dict(groups=args.groups, steps=args.steps,
                   dispatches=args.dispatches, margin=args.margin, mode=args.mode)
    if args.cap is not None:
        options["cap"] = args.cap
    config = config_for_seed(args.tensor, args.seed, **options)
    relay = CooperativeSimdRelay(args.run_dir, config)
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
    payload.update(exact=True, selected_mode=config.selected_mode,
                   hardware_lanes=config.hardware_lanes)
    print(json.dumps(payload, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
