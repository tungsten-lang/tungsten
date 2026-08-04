#!/usr/bin/env python3
"""Matched whole-language A/B/GMP timing for consumed bitwise destinations."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import re
import statistics
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "benchmarks/big_math/compound_bitwise_loops.w"
GMP_SOURCE = ROOT / "benchmarks/big_math/compound_bitwise_loops_gmp.c"
LINE = re.compile(
    r"^compound\t(and|or|xor|shift)\t(\d+)\t(\d+)\t"
    r"([0-9.eE+-]+)\t(\d+)$"
)


def output(command: list[str], default: str = "unknown") -> str:
    try:
        return subprocess.check_output(command, text=True, stderr=subprocess.DEVNULL).strip()
    except (OSError, subprocess.CalledProcessError):
        return default


def run(command: list[str], *, env: dict[str, str] | None = None) -> None:
    subprocess.run(command, cwd=ROOT, env=env, check=True)


def machine() -> dict[str, object]:
    return {
        "hostname": platform.node(),
        "machine": platform.machine(),
        "processor": platform.processor() or "unknown",
        "platform": platform.platform(),
        "logical_cpus": os.cpu_count(),
        "load_average": list(os.getloadavg()),
        "power": output(["pmset", "-g", "batt"]),
        "clang": output(["clang", "--version"]).splitlines()[0],
        "target_triple": output(["clang", "-dumpmachine"]),
        "gmp_version": output(["pkg-config", "--modversion", "gmp"]),
        "git_head": output(["git", "rev-parse", "HEAD"]),
    }


def build_program(compiler: Path, binary: Path, ll_path: Path, enabled: bool) -> None:
    env = os.environ.copy()
    env["TUNGSTEN_ROOT"] = str(ROOT)
    env["TUNGSTEN_LL_PATH"] = str(ll_path)
    env["TUNGSTEN_BIGINT_MUTATE_UNIQUE"] = "1"
    env["TUNGSTEN_BIGINT_BITWISE_MUT"] = "1" if enabled else "0"
    env["TUNGSTEN_BIGINT_SHIFT_MUT"] = "1" if enabled else "0"
    run([
        str(compiler), "-o", str(binary), "--release", "--native", "--fast",
        str(SOURCE),
    ], env=env)


def build_gmp(binary: Path) -> None:
    flags = output(["pkg-config", "--cflags", "gmp"], "").split()
    libs = output(["pkg-config", "--libs", "gmp"], "").split()
    if not libs:
        raise RuntimeError("GMP is required (pkg-config gmp failed)")
    run([
        "clang", "-O3", "-DNDEBUG", "-mcpu=native", *flags,
        str(GMP_SOURCE), *libs, "-o", str(binary),
    ])


def sample(binary: Path, operation: str, limbs: int, iterations: int) -> tuple[float, int]:
    text = subprocess.check_output(
        [str(binary), operation, str(limbs), str(iterations)],
        cwd=ROOT, text=True,
    ).strip()
    match = LINE.match(text)
    if not match:
        raise RuntimeError(f"unexpected benchmark output from {binary}: {text!r}")
    if int(match.group(2)) != limbs or int(match.group(3)) != iterations:
        raise RuntimeError(f"benchmark echoed the wrong cell: {text!r}")
    return float(match.group(4)), int(match.group(5))


def calibrate(binaries: list[Path], operation: str, limbs: int, target_ms: float) -> int:
    iterations = 1001
    target_ns = target_ms * 1e6
    while True:
        elapsed = [sample(path, operation, limbs, iterations)[0] * iterations for path in binaries]
        fastest = min(elapsed)
        if fastest >= target_ns:
            return iterations | 1
        scale = max(1.4, target_ns / max(fastest, 1.0) * 1.05)
        iterations = min(int(iterations * scale) + 1, 2_000_000_001)
        if iterations >= 2_000_000_001:
            return iterations


def iqr(values: list[float]) -> float:
    ordered = sorted(values)
    half = len(ordered) // 2
    lower = ordered[:half]
    upper = ordered[-half:]
    return statistics.median(upper) - statistics.median(lower)


def parse_csv(value: str, allowed: set[str] | None = None) -> list[str]:
    result = [part.strip() for part in value.split(",") if part.strip()]
    if not result or (allowed is not None and any(part not in allowed for part in result)):
        raise argparse.ArgumentTypeError(f"invalid comma-separated list: {value}")
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--operations", default="and,or,xor,shift")
    parser.add_argument("--sizes", default="4,16,64")
    parser.add_argument("--rounds", type=int, default=9)
    parser.add_argument("--target-ms", type=float, default=110.0)
    parser.add_argument(
        "--control-binary", type=Path,
        help="compare current candidate with an already-built whole-language control",
    )
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    operations = parse_csv(args.operations, {"and", "or", "xor", "shift"})
    sizes = [int(value) for value in parse_csv(args.sizes)]
    if any(size not in {2, 4, 8, 16, 32, 64, 128, 256} for size in sizes):
        parser.error("sizes must be selected from 2,4,8,16,32,64,128,256")
    if args.rounds < 9 or args.target_ms < 110.0:
        parser.error("acceptance runs require >=9 rounds and >=110 ms")

    metadata = machine()
    records: list[dict[str, object]] = []
    with tempfile.TemporaryDirectory(prefix="tungsten-compound-bitwise-") as raw_temp:
        temp = Path(raw_temp)
        compiler = temp / "tungsten-compiler"
        candidate = temp / "compound-candidate"
        control = args.control_binary.resolve() if args.control_binary else temp / "compound-control"
        gmp = temp / "compound-gmp"
        candidate_ll = temp / "compound-candidate.ll"
        control_ll = temp / "compound-control.ll"

        print("Building compiler release/native/fast...", flush=True)
        run([
            str(ROOT / "bin/tungsten"), "-o", str(compiler),
            "--release", "--native", "--fast", str(ROOT / "compiler/tungsten.w"),
        ])
        print("Building candidate, control, and public-GMP twin...", flush=True)
        build_program(compiler, candidate, candidate_ll, True)
        if args.control_binary:
            if not control.is_file():
                parser.error(f"control binary does not exist: {control}")
            control_ll = Path(str(control) + ".ll")
        else:
            build_program(compiler, control, control_ll, False)
        build_gmp(gmp)

        binaries = {"candidate": candidate, "control": control, "gmp": gmp}
        for operation in operations:
            for limbs in sizes:
                iterations = calibrate(list(binaries.values()), operation, limbs, args.target_ms)
                samples = {name: [] for name in binaries}
                checksums = {name: [] for name in binaries}
                names = list(binaries)
                for round_index in range(args.rounds):
                    offset = round_index % len(names)
                    order = names[offset:] + names[:offset]
                    for name in order:
                        ns, checksum = sample(binaries[name], operation, limbs, iterations)
                        samples[name].append(ns)
                        checksums[name].append(checksum)
                unique_checksums = {value for values in checksums.values() for value in values}
                if len(unique_checksums) != 1:
                    raise RuntimeError(
                        f"checksum mismatch for {operation}@{limbs}: {checksums}"
                    )
                medians = {name: statistics.median(values) for name, values in samples.items()}
                spreads = {name: iqr(values) for name, values in samples.items()}
                record = {
                    "operation": operation,
                    "limbs": limbs,
                    "iterations": iterations,
                    "rounds": args.rounds,
                    "target_ms": args.target_ms,
                    "candidate_ns": medians["candidate"],
                    "control_ns": medians["control"],
                    "gmp_ns": medians["gmp"],
                    "candidate_iqr_ns": spreads["candidate"],
                    "control_iqr_ns": spreads["control"],
                    "gmp_iqr_ns": spreads["gmp"],
                    "candidate_over_control": medians["candidate"] / medians["control"],
                    "candidate_over_gmp": medians["candidate"] / medians["gmp"],
                    "control_over_gmp": medians["control"] / medians["gmp"],
                    "checksum": unique_checksums.pop(),
                    "samples": samples,
                }
                records.append(record)
                print(
                    f"{operation:5s}@{limbs:3d} candidate/control "
                    f"{record['candidate_over_control']:.3f}  candidate/GMP "
                    f"{record['candidate_over_gmp']:.3f}",
                    flush=True,
                )

        payload = {
            "schema": "tungsten.bigint.compound-bitwise-ab/v1",
            "machine": metadata,
            "build": {
                "flags": ["--release", "--native", "--fast"],
                "candidate_env": {
                    "TUNGSTEN_BIGINT_MUTATE_UNIQUE": 1,
                    "TUNGSTEN_BIGINT_BITWISE_MUT": 1,
                    "TUNGSTEN_BIGINT_SHIFT_MUT": 1,
                },
                "control_env": {
                    "prebuilt": str(control) if args.control_binary else None,
                    "TUNGSTEN_BIGINT_MUTATE_UNIQUE": 1,
                    "TUNGSTEN_BIGINT_BITWISE_MUT": 1 if args.control_binary else 0,
                    "TUNGSTEN_BIGINT_SHIFT_MUT": 1 if args.control_binary else 0,
                },
                "sha256": {
                    name: hashlib.sha256(path.read_bytes()).hexdigest()
                    for name, path in {
                        "compiler": compiler,
                        "candidate": candidate,
                        "control": control,
                        "gmp": gmp,
                        "candidate_ll": candidate_ll,
                        "control_ll": control_ll,
                    }.items() if path.is_file()
                },
            },
            "records": records,
        }
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(payload, indent=2) + "\n")
        print(f"Wrote {args.output}", flush=True)


if __name__ == "__main__":
    main()
