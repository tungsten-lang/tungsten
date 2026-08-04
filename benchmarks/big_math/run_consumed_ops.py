#!/usr/bin/env python3
"""Measure ideal reusable destinations for remaining BigInt operation groups."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import platform
import re
import statistics
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / "benchmarks/big_math/run.sh"
LINE = re.compile(
    r"consumed\t(and|or|xor|shift|pow3)\t(\d+)\t(\d+)\t"
    r"(immutable|consume)\t([0-9.]+)\t(\d+)"
)
OPERATIONS = ("and", "or", "xor", "shift", "pow3")
WIDTHS = (4, 16, 64)
LANES = ("immutable", "consume")


def run(command: list[str], *, env: dict[str, str] | None = None) -> str:
    completed = subprocess.run(
        command, cwd=ROOT, env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    if completed.returncode:
        detail = completed.stderr.strip() or completed.stdout.strip()
        raise RuntimeError(f"command failed: {' '.join(command)}\n{detail}")
    return completed.stdout.strip()


def output(command: list[str], fallback: str = "unknown") -> str:
    try:
        return run(command) or fallback
    except (OSError, RuntimeError):
        return fallback


def percentile(values: list[float], fraction: float) -> float:
    ordered = sorted(values)
    position = (len(ordered) - 1) * fraction
    lower, upper = math.floor(position), math.ceil(position)
    if lower == upper:
        return ordered[lower]
    weight = position - lower
    return ordered[lower] * (1.0 - weight) + ordered[upper] * weight


def iqr(values: list[float]) -> float:
    return percentile(values, 0.75) - percentile(values, 0.25)


def geomean(values: list[float]) -> float:
    return math.exp(sum(math.log(value) for value in values) / len(values))


def machine() -> dict:
    cpu = output(["sysctl", "-n", "machdep.cpu.brand_string"], "")
    return {
        "cpu": cpu or platform.processor() or "unknown",
        "machine": platform.machine(),
        "platform": platform.platform(),
        "logical_cpus": os.cpu_count(),
        "load_average": list(os.getloadavg()),
        "power": output(["pmset", "-g", "batt"], ""),
        "compiler": output(["clang", "--version"]).splitlines()[0],
        "target_triple": output(["clang", "-dumpmachine"]),
    }


def sample(binary: Path, operation: str, limbs: int, iterations: int,
           lane: str) -> tuple[float, int]:
    text = run([
        str(binary), "--bench-consumed-op", operation,
        str(limbs), str(iterations), lane,
    ])
    match = LINE.fullmatch(text)
    if not match or (match.group(1), match.group(4)) != (operation, lane):
        raise RuntimeError(f"unexpected {operation}/{lane} output: {text!r}")
    if (int(match.group(2)), int(match.group(3))) != (limbs, iterations):
        raise RuntimeError(f"parameter mismatch for {operation}/{lane}")
    return float(match.group(5)), int(match.group(6))


def calibrate(binary: Path, operation: str, limbs: int, lane: str,
              target_ms: float) -> int:
    probe = 10_001
    ns, _ = sample(binary, operation, limbs, probe, lane)
    estimate = int(target_ms * 1_000_000.0 / max(ns, 0.001))
    return max(1001, min(100_000_001, estimate | 1))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--rounds", type=int, default=9)
    parser.add_argument("--target-ms", type=float, default=110.0)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.rounds < 9 or args.target_ms < 110.0:
        parser.error("acceptance runs require >=9 rounds and >=110 ms")

    start_machine = machine()
    records = []
    with tempfile.TemporaryDirectory(prefix="tungsten-consumed-ops-") as temp:
        directory = Path(temp)
        binary = directory / "bench-big-math"
        env = os.environ.copy()
        env["BENCH_OUT"] = str(binary)
        env["BENCH_PROFILE"] = str(binary) + ".profile"
        print("Building boxed consumed-operation prototype...", flush=True)
        run([str(BUILD), "--build-only"], env=env)
        binary_hash = hashlib.sha256(binary.read_bytes()).hexdigest()
        for operation in OPERATIONS:
            for limbs in WIDTHS:
                iterations = {
                    lane: calibrate(
                        binary, operation, limbs, lane, args.target_ms
                    )
                    for lane in LANES
                }
                samples = {lane: [] for lane in LANES}
                checksums = {lane: [] for lane in LANES}
                for round_index in range(args.rounds):
                    order = LANES if round_index % 2 == 0 else LANES[::-1]
                    print(
                        f"{operation}@{limbs} round {round_index + 1}/{args.rounds}: "
                        + " then ".join(order), flush=True,
                    )
                    for lane in order:
                        ns, checksum = sample(
                            binary, operation, limbs, iterations[lane], lane
                        )
                        samples[lane].append(ns)
                        checksums[lane].append(checksum)
                if any(len(set(checksums[lane])) != 1 for lane in LANES):
                    raise RuntimeError(f"unstable checksum for {operation}@{limbs}")
                if checksums["immutable"][0] != checksums["consume"][0]:
                    raise RuntimeError(f"semantic mismatch for {operation}@{limbs}")
                paired = [
                    candidate / control
                    for control, candidate in zip(
                        samples["immutable"], samples["consume"], strict=True
                    )
                ]
                records.append({
                    "operation": operation,
                    "limbs": limbs,
                    "iterations": iterations,
                    "median_ns": {
                        lane: statistics.median(samples[lane]) for lane in LANES
                    },
                    "consume_over_immutable_paired_median": statistics.median(paired),
                    "consume_over_immutable_paired_iqr": iqr(paired),
                    "samples_ns": samples,
                    "checksums": {lane: checksums[lane][0] for lane in LANES},
                    "paired_ratios": paired,
                })

    ratios = [record["consume_over_immutable_paired_median"] for record in records]
    by_operation = {}
    for operation in OPERATIONS:
        selected = [
            record["consume_over_immutable_paired_median"]
            for record in records if record["operation"] == operation
        ]
        by_operation[operation] = {
            "cells": len(selected),
            "wins": sum(ratio < 1.0 for ratio in selected),
            "geomean": geomean(selected),
            "regressions_over_5_percent": sum(ratio > 1.05 for ratio in selected),
        }
    artifact = {
        "schema": 1,
        "suggestion": "GLM-01",
        "experiment": {
            "label": "remaining-operation reusable destination upper bound",
            "rounds": args.rounds,
            "target_ms": args.target_ms,
            "widths": list(WIDTHS),
            "binary_sha256": binary_hash,
        },
        "metadata": {
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "git_commit": output(["git", "rev-parse", "HEAD"]),
            "git_dirty_tracked": bool(output([
                "git", "status", "--short", "--untracked-files=no",
            ])),
            "machine_start": start_machine,
            "machine_end": machine(),
            "methodology": (
                "full boxed immutable control with ordinary pool handoff; "
                "operation-specific ideal caller-owned destination prototype; "
                "separate processes, alternating order, lane-specific >=110 ms "
                "calibration, odd iteration counts, exact checksum equality"
            ),
            "limitation": (
                "upper-bound runtime prototype only; no new source compound "
                "syntax or compiler liveness lowering is inferred"
            ),
        },
        "summary": {
            "cells": len(records),
            "wins": sum(ratio < 1.0 for ratio in ratios),
            "consume_over_immutable_geomean": geomean(ratios),
            "regressions_over_5_percent": sum(ratio > 1.05 for ratio in ratios),
            "by_operation": by_operation,
        },
        "results": records,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(artifact, indent=2) + "\n")
    print(json.dumps(artifact["summary"], sort_keys=True))


if __name__ == "__main__":
    main()
