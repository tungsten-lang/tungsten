#!/usr/bin/env python3
"""Compare locked mutable and immutable-CAS shared BigInt counters."""

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
LINE = re.compile(r"atomic\t(mutex|cas)\t(\d+)\t(\d+)\t([0-9.]+)\t(\d+)")
MODES = ("mutex", "cas")


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


def sample(binary: Path, mode: str, threads: int,
           updates: int) -> tuple[float, int]:
    text = run([
        str(binary), "--bench-atomic-bigint", mode,
        str(threads), str(updates),
    ])
    match = LINE.fullmatch(text)
    if not match or match.group(1) != mode:
        raise RuntimeError(f"unexpected {mode} output: {text!r}")
    if (int(match.group(2)), int(match.group(3))) != (threads, updates):
        raise RuntimeError(f"parameter mismatch for {mode}")
    return float(match.group(4)), int(match.group(5))


def calibrate(binary: Path, mode: str, threads: int,
              target_ms: float) -> int:
    probe_updates = 2001
    ns, _ = sample(binary, mode, threads, probe_updates)
    per_thread = int(target_ms * 1_000_000.0 / max(ns * threads, 0.001))
    # The safe CAS prototype retains published immutable generations until
    # process exit. Bound each sample to two million result boxes.
    per_thread = min(per_thread, 2_000_000 // threads)
    return max(1001, per_thread | 1)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--rounds", type=int, default=9)
    parser.add_argument("--target-ms", type=float, default=110.0)
    parser.add_argument("--threads", default="2,4,8")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    threads_list = [int(value) for value in args.threads.split(",")]
    if args.rounds < 9 or args.target_ms < 110.0:
        parser.error("acceptance runs require >=9 rounds and >=110 ms")
    if not threads_list or any(value < 1 or value > 16 for value in threads_list):
        parser.error("threads must be in 1..16")

    start_machine = machine()
    records = []
    with tempfile.TemporaryDirectory(prefix="tungsten-atomic-bigint-") as temp:
        directory = Path(temp)
        binary = directory / "bench-big-math"
        env = os.environ.copy()
        env["BENCH_OUT"] = str(binary)
        env["BENCH_PROFILE"] = str(binary) + ".profile"
        print("Building boxed BigInt atomic prototype...", flush=True)
        run([str(BUILD), "--build-only"], env=env)
        binary_hash = hashlib.sha256(binary.read_bytes()).hexdigest()
        for threads in threads_list:
            updates = {
                mode: calibrate(binary, mode, threads, args.target_ms)
                for mode in MODES
            }
            samples = {mode: [] for mode in MODES}
            checksums = {mode: [] for mode in MODES}
            for round_index in range(args.rounds):
                order = MODES if round_index % 2 == 0 else MODES[::-1]
                print(
                    f"threads={threads} round {round_index + 1}/{args.rounds}: "
                    + " then ".join(order), flush=True,
                )
                for mode in order:
                    ns, checksum = sample(
                        binary, mode, threads, updates[mode]
                    )
                    samples[mode].append(ns)
                    checksums[mode].append(checksum)
            if any(len(set(checksums[mode])) != 1 for mode in MODES):
                raise RuntimeError(f"unstable checksum at {threads} threads")
            paired = [
                cas / mutex
                for mutex, cas in zip(samples["mutex"], samples["cas"], strict=True)
            ]
            records.append({
                "threads": threads,
                "updates_per_thread": updates,
                "median_ns_per_update": {
                    mode: statistics.median(samples[mode]) for mode in MODES
                },
                "cas_over_mutex_paired_median": statistics.median(paired),
                "cas_over_mutex_paired_iqr": iqr(paired),
                "samples_ns_per_update": samples,
                "checksums": {mode: checksums[mode][0] for mode in MODES},
                "paired_ratios": paired,
            })

    ratios = [record["cas_over_mutex_paired_median"] for record in records]
    artifact = {
        "schema": 1,
        "suggestion": "GEMMA-17",
        "experiment": {
            "label": "shared boxed BigInt mutex versus immutable CAS",
            "rounds": args.rounds,
            "target_ms": args.target_ms,
            "threads": threads_list,
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
                "full boxed updates after a start barrier; mutex lane mutates "
                "the unique value under lock; CAS lane publishes immutable "
                "boxes and safely retains old generations because no BigInt "
                "hazard-pointer/epoch reclamation contract exists; process per sample"
            ),
        },
        "summary": {
            "cells": len(records),
            "cas_wins": sum(ratio < 1.0 for ratio in ratios),
            "cas_over_mutex_geomean": geomean(ratios),
            "cas_regressions_over_5_percent": sum(ratio > 1.05 for ratio in ratios),
        },
        "results": records,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(artifact, indent=2) + "\n")
    print(json.dumps(artifact["summary"], sort_keys=True))


if __name__ == "__main__":
    main()
