#!/usr/bin/env python3
"""Run a controlled boxed BigInt A/B between two compile-time variants."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import platform
import re
import shlex
import statistics
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / "benchmarks" / "big_math" / "run.sh"
DEFAULT_CFLAGS = (
    "-O3 -DNDEBUG -mcpu=native -falign-functions=64 "
    "-Wno-deprecated-declarations"
)


def run_checked(
    command: list[str], *, env: dict[str, str] | None = None
) -> str:
    completed = subprocess.run(
        command,
        cwd=ROOT,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip()
        raise RuntimeError(
            f"command failed ({completed.returncode}): "
            f"{shlex.join(command)}" + (f"\n{detail}" if detail else "")
        )
    return completed.stdout


def command_output(command: list[str], fallback: str = "unknown") -> str:
    try:
        return run_checked(command).strip() or fallback
    except (FileNotFoundError, RuntimeError):
        return fallback


def parse_csv(value: str, *, integers: bool = False) -> list[Any]:
    pieces = [piece.strip() for piece in value.split(",") if piece.strip()]
    if not pieces:
        raise argparse.ArgumentTypeError("expected a non-empty comma list")
    if not integers:
        return pieces
    try:
        result = [int(piece) for piece in pieces]
    except ValueError as error:
        raise argparse.ArgumentTypeError("sizes must be integers") from error
    if any(item <= 0 or item > 1_048_576 for item in result):
        raise argparse.ArgumentTypeError("sizes must be in 1..1048576 limbs")
    return result


def percentile(values: list[float], fraction: float) -> float:
    ordered = sorted(values)
    if len(ordered) == 1:
        return ordered[0]
    position = (len(ordered) - 1) * fraction
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return ordered[lower]
    weight = position - lower
    return ordered[lower] * (1.0 - weight) + ordered[upper] * weight


def iqr(values: list[float]) -> float:
    return percentile(values, 0.75) - percentile(values, 0.25)


def geomean(values: list[float]) -> float:
    return math.exp(sum(math.log(value) for value in values) / len(values))


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def power_state() -> dict[str, Any]:
    if platform.system() != "Darwin":
        return {}
    output = command_output(["pmset", "-g", "batt"], "")
    source_match = re.search(r"Now drawing from '([^']+)'", output)
    percent_match = re.search(r"(\d+)%", output)
    result: dict[str, Any] = {}
    if source_match:
        result["source"] = source_match.group(1)
    if percent_match:
        result["battery_percent"] = int(percent_match.group(1))
    return result


def machine_metadata(cflags: str) -> dict[str, Any]:
    cpu = command_output(["sysctl", "-n", "machdep.cpu.brand_string"], "")
    if not cpu:
        cpu = platform.processor() or "unknown"
    load = list(os.getloadavg()) if hasattr(os, "getloadavg") else []
    compiler = os.environ.get("CC", "clang")
    return {
        "machine": platform.machine(),
        "platform": platform.platform(),
        "cpu": cpu,
        "logical_cpus": os.cpu_count(),
        "load_average": load,
        "power": power_state(),
        "compiler_command": compiler,
        "compiler": command_output([compiler, "--version"]).splitlines()[0],
        "compiler_flags": cflags,
        "target_triple": command_output([compiler, "-dumpmachine"]),
    }


def build_variant(output: Path, cflags: str) -> None:
    env = os.environ.copy()
    env["BENCH_OUT"] = str(output)
    env["BENCH_PROFILE"] = str(output) + ".profile"
    env["CFLAGS"] = cflags
    run_checked([str(BUILD), "--build-only"], env=env)


def run_sweep(
    binary: Path,
    operation: str,
    sizes: list[int],
    target_ms: float,
    *,
    tungsten_only: bool,
) -> dict[int, dict[str, float]]:
    output = run_checked(
        [
            str(binary),
            "--bench-tungsten-sweep" if tungsten_only else "--bench-boxed-sweep",
            operation,
            ",".join(str(size) for size in sizes),
            "1",
            f"{target_ms:g}",
        ]
    )
    rows: dict[int, dict[str, float]] = {}
    for line in output.splitlines():
        fields = line.split("\t")
        if len(fields) != 8 or fields[0] != "boxed" or fields[1] != operation:
            raise RuntimeError(f"unexpected sweep output: {line}")
        limbs = int(fields[2])
        rows[limbs] = {
            "iterations": int(fields[3]),
            "tungsten_ns": float(fields[4]),
            "gmp_ns": float(fields[5]),
        }
    if list(rows) != sizes:
        raise RuntimeError(
            f"sweep row mismatch for {operation}: expected {sizes}, "
            f"got {list(rows)}"
        )
    return rows


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "build two isolated runtime variants and compare boxed BigInt "
            "operations with alternating order"
        )
    )
    parser.add_argument("--label", required=True, help="experiment label")
    parser.add_argument("--operations", required=True, help="comma-separated operations")
    parser.add_argument("--sizes", required=True, help="comma-separated limb counts")
    parser.add_argument(
        "--baseline-extra-flags",
        default="",
        help="flags appended only to the baseline build",
    )
    parser.add_argument(
        "--candidate-extra-flags",
        default="",
        help="flags appended only to the candidate build",
    )
    parser.add_argument("--baseline-name", default="baseline")
    parser.add_argument("--candidate-name", default="candidate")
    parser.add_argument(
        "--tungsten-only",
        action="store_true",
        help=(
            "time only the Tungsten variant lanes (GMP correctness checks "
            "still run; use a separately recorded matrix for GMP timing)"
        ),
    )
    parser.add_argument("--rounds", type=int, default=9)
    parser.add_argument("--target-ms", type=float, default=110.0)
    parser.add_argument("--output", type=Path, required=True)
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    operations = parse_csv(args.operations)
    sizes = parse_csv(args.sizes, integers=True)
    if args.rounds <= 0:
        parser.error("--rounds must be positive")
    if args.target_ms <= 0:
        parser.error("--target-ms must be positive")
    if args.baseline_name == args.candidate_name:
        parser.error("baseline and candidate names must differ")
    acceptance_eligible = args.rounds >= 9 and args.target_ms >= 110.0
    if not acceptance_eligible:
        print(
            "NON-ACCEPTANCE RUN: suggestion dispositions require at least "
            "9 rounds and a 110 ms target",
            file=sys.stderr,
        )

    base_cflags = " ".join(
        part for part in (DEFAULT_CFLAGS, args.baseline_extra_flags.strip()) if part
    )
    candidate_cflags = " ".join(
        part for part in (DEFAULT_CFLAGS, args.candidate_extra_flags.strip()) if part
    )
    variants = (args.baseline_name, args.candidate_name)
    samples: dict[tuple[str, str, int], list[dict[str, float]]] = {
        (variant, operation, limbs): []
        for variant in variants
        for operation in operations
        for limbs in sizes
    }

    start_machine = machine_metadata(base_cflags)
    with tempfile.TemporaryDirectory(prefix="tungsten-bignum-ab-") as temp:
        temp_dir = Path(temp)
        binaries = {
            args.baseline_name: temp_dir / "baseline",
            args.candidate_name: temp_dir / "candidate",
        }
        print(f"Building {args.baseline_name} variant...", file=sys.stderr)
        build_variant(binaries[args.baseline_name], base_cflags)
        print(f"Building {args.candidate_name} variant...", file=sys.stderr)
        build_variant(binaries[args.candidate_name], candidate_cflags)
        binary_hashes = {
            variant: file_sha256(binary) for variant, binary in binaries.items()
        }

        for round_index in range(args.rounds):
            order = list(variants)
            if round_index & 1:
                order.reverse()
            print(
                f"Round {round_index + 1}/{args.rounds}: " + " then ".join(order),
                file=sys.stderr,
            )
            for variant in order:
                for operation in operations:
                    rows = run_sweep(
                        binaries[variant], operation, sizes, args.target_ms,
                        tungsten_only=args.tungsten_only,
                    )
                    for limbs, row in rows.items():
                        samples[(variant, operation, limbs)].append(row)

    results = []
    for operation in operations:
        for limbs in sizes:
            baseline = samples[(args.baseline_name, operation, limbs)]
            candidate = samples[(args.candidate_name, operation, limbs)]
            baseline_ns = [sample["tungsten_ns"] for sample in baseline]
            candidate_ns = [sample["tungsten_ns"] for sample in candidate]
            paired_ratios = [
                after / before
                for before, after in zip(baseline_ns, candidate_ns, strict=True)
            ]
            baseline_gmp_ratios = None if args.tungsten_only else [
                sample["tungsten_ns"] / sample["gmp_ns"] for sample in baseline
            ]
            candidate_gmp_ratios = None if args.tungsten_only else [
                sample["tungsten_ns"] / sample["gmp_ns"] for sample in candidate
            ]
            ratio = statistics.median(paired_ratios)
            results.append(
                {
                    "operation": operation,
                    "limbs": limbs,
                    "bits": limbs * 64,
                    "baseline_ns_median": statistics.median(baseline_ns),
                    "baseline_ns_iqr": iqr(baseline_ns),
                    "candidate_ns_median": statistics.median(candidate_ns),
                    "candidate_ns_iqr": iqr(candidate_ns),
                    "candidate_over_baseline_paired_median": ratio,
                    "candidate_over_baseline_paired_iqr": iqr(paired_ratios),
                    "speedup": 1.0 / ratio,
                    "baseline_over_gmp_median": (
                        None if baseline_gmp_ratios is None
                        else statistics.median(baseline_gmp_ratios)
                    ),
                    "candidate_over_gmp_median": (
                        None if candidate_gmp_ratios is None
                        else statistics.median(candidate_gmp_ratios)
                    ),
                    "samples": {
                        args.baseline_name: baseline,
                        args.candidate_name: candidate,
                        "candidate_over_baseline_paired": paired_ratios,
                    },
                }
            )

    ratios = [row["candidate_over_baseline_paired_median"] for row in results]
    document = {
        "metadata": {
            "command": shlex.join([sys.executable, *sys.argv]),
            "generated_at": datetime.now(timezone.utc).astimezone().isoformat(),
            "git_commit": command_output(["git", "rev-parse", "HEAD"]),
            "git_dirty_tracked": bool(
                command_output(
                    ["git", "status", "--porcelain", "--untracked-files=no"],
                    "",
                )
            ),
            "gmp_version": command_output(["pkg-config", "--modversion", "gmp"]),
            "start_machine": start_machine,
            "end_machine": machine_metadata(base_cflags),
            "methodology": (
                "isolated same-source builds; variant order alternates each round; "
                "each point is a full boxed immutable Tungsten operation with the "
                "previous result live; paired median and IQR are computed across "
                "outer rounds; "
                + (
                    "GMP is used as a public-API correctness oracle but is not timed "
                    "in this variant-isolation run"
                    if args.tungsten_only
                    else "GMP remains the public-API within-build reference"
                )
            ),
            "acceptance_eligible": acceptance_eligible,
        },
        "experiment": {
            "label": args.label,
            "baseline_name": args.baseline_name,
            "candidate_name": args.candidate_name,
            "baseline_flags": base_cflags,
            "candidate_flags": candidate_cflags,
            "binary_sha256": binary_hashes,
            "operations": operations,
            "sizes": sizes,
            "rounds": args.rounds,
            "target_ms": args.target_ms,
            "tungsten_only": args.tungsten_only,
        },
        "results": results,
        "summary": {
            "acceptance_eligible": acceptance_eligible,
            "cells": len(results),
            "candidate_wins": sum(ratio < 1.0 for ratio in ratios),
            "candidate_losses": sum(ratio > 1.0 for ratio in ratios),
            "candidate_over_baseline_geomean": geomean(ratios),
            "regressions_over_5_percent": sum(ratio > 1.05 for ratio in ratios),
        },
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(document, indent=2) + "\n")

    print(
        "op\tlimbs\tbaseline_ns\tcandidate_ns\tcandidate/base\tT/GMP candidate"
    )
    for row in results:
        print(
            f"{row['operation']}\t{row['limbs']}\t"
            f"{row['baseline_ns_median']:.3f}\t"
            f"{row['candidate_ns_median']:.3f}\t"
            f"{row['candidate_over_baseline_paired_median']:.4f}\t"
            + (
                "n/a" if row["candidate_over_gmp_median"] is None
                else f"{row['candidate_over_gmp_median']:.4f}"
            )
        )
    print(json.dumps(document["summary"], sort_keys=True))
    print(f"wrote {args.output}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as error:
        print(f"run_variant_ab.py: {error}", file=sys.stderr)
        raise SystemExit(1)
