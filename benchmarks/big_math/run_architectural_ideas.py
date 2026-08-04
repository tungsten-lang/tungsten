#!/usr/bin/env python3
"""Measure full-language upper bounds for four BigInt architecture ideas."""

from __future__ import annotations

import argparse
import hashlib
import itertools
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
SOURCE = ROOT / "benchmarks/big_math/architectural_ideas.w"
LINE = re.compile(r"([^\t]+)\t(\d+)\t(\d+)\t(\d+)\t([0-9.]+)\t(-?\d+)")
EXPERIMENTS = (
    ("GEMMA-05", "jit-chain", "jit-primitive", ((4, 8), (16, 8), (64, 8))),
    ("GEMMA-10", "loop-serial", "loop-four", ((4, 64), (16, 64), (64, 64))),
    ("GEMMA-11", "fixed-decimal", "fixed-scaled", ((2, 10),)),
    ("GEMMA-18", "padic-generic", "padic-primitive", ((4, 65537), (16, 65537), (64, 65537))),
)


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


def sample(binary: Path, lane: str, width: int, auxiliary: int,
           iterations: int) -> tuple[float, int]:
    text = run([
        str(binary), lane, str(width), str(auxiliary), str(iterations),
    ])
    match = LINE.fullmatch(text)
    if not match or match.group(1) != lane:
        raise RuntimeError(f"unexpected {lane} output: {text!r}")
    observed = tuple(int(match.group(i)) for i in (2, 3, 4))
    if observed != (width, auxiliary, iterations):
        raise RuntimeError(f"parameter mismatch for {lane}: {observed}")
    return float(match.group(5)), int(match.group(6))


def calibrate(binary: Path, lane: str, width: int, auxiliary: int,
              target_ms: float) -> int:
    iterations = 1
    for _ in range(8):
        ns, _ = sample(binary, lane, width, auxiliary, iterations)
        estimate = max(1, int(target_ms * 1_000_000.0 / max(ns, 0.001)))
        estimate |= 1
        if 0.5 * estimate <= iterations <= 2.0 * estimate:
            return estimate
        iterations = min(estimate, 200_000_001)
    return iterations | 1


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--rounds", type=int, default=9)
    parser.add_argument("--target-ms", type=float, default=110.0)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.rounds < 9 or args.target_ms < 110.0:
        parser.error("acceptance runs require >=9 rounds and >=110 ms")

    start_machine = machine()
    records: list[dict] = []
    with tempfile.TemporaryDirectory(prefix="tungsten-architecture-ideas-") as temp:
        directory = Path(temp)
        compiler = directory / "tungsten-compiler"
        binary = directory / "architectural-ideas"
        ll_path = directory / "architectural-ideas.ll"
        print("Building current compiler release/native/fast...", flush=True)
        run([
            str(ROOT / "bin/tungsten"), "-o", str(compiler),
            "--release", "--native", "--fast",
            str(ROOT / "compiler/tungsten.w"),
        ])
        env = os.environ.copy()
        env["TUNGSTEN_ROOT"] = str(ROOT)
        env["TUNGSTEN_LL_PATH"] = str(ll_path)
        print("Building architectural benchmark release/native/fast...", flush=True)
        run([
            str(compiler), "-o", str(binary),
            "--release", "--native", "--fast", str(SOURCE),
        ], env=env)
        hashes = {
            "compiler": hashlib.sha256(compiler.read_bytes()).hexdigest(),
            "binary": hashlib.sha256(binary.read_bytes()).hexdigest(),
        }

        for suggestion, control, candidate, cells in EXPERIMENTS:
            for width, auxiliary in cells:
                lanes = (control, candidate)
                iterations = {
                    lane: calibrate(binary, lane, width, auxiliary, args.target_ms)
                    for lane in lanes
                }
                samples = {lane: [] for lane in lanes}
                checksums = {lane: [] for lane in lanes}
                for round_index in range(args.rounds):
                    order = lanes if round_index % 2 == 0 else lanes[::-1]
                    print(
                        f"{suggestion} {width}/{auxiliary} round "
                        f"{round_index + 1}/{args.rounds}: " + " then ".join(order),
                        flush=True,
                    )
                    for lane in order:
                        ns, checksum = sample(
                            binary, lane, width, auxiliary, iterations[lane]
                        )
                        samples[lane].append(ns)
                        checksums[lane].append(checksum)
                if len(set(checksums[control])) != 1 or len(set(checksums[candidate])) != 1:
                    raise RuntimeError(f"unstable checksum for {suggestion} {width}")
                # Paired modular lanes use odd iteration counts, so their XOR
                # checksums must be identical. Fixed-scale lanes have different
                # calibrated counts and are checked against their closed form.
                if suggestion != "GEMMA-11" and checksums[control][0] != checksums[candidate][0]:
                    raise RuntimeError(f"semantic mismatch for {suggestion} {width}")
                if suggestion == "GEMMA-11":
                    for lane in lanes:
                        expected = 1_234_567 + iterations[lane]
                        if checksums[lane][0] != expected:
                            raise RuntimeError(f"fixed-scale mismatch for {lane}")
                paired = [
                    after / before
                    for before, after in zip(samples[control], samples[candidate], strict=True)
                ]
                records.append({
                    "suggestion": suggestion,
                    "control": control,
                    "candidate": candidate,
                    "width_limbs": width,
                    "auxiliary": auxiliary,
                    "iterations": iterations,
                    "median_ns": {lane: statistics.median(samples[lane]) for lane in lanes},
                    "candidate_over_control_paired_median": statistics.median(paired),
                    "candidate_over_control_paired_iqr": iqr(paired),
                    "samples_ns": samples,
                    "checksums": {lane: checksums[lane][0] for lane in lanes},
                    "paired_ratios": paired,
                })

    summaries = {}
    for suggestion, _, _, _ in EXPERIMENTS:
        ratios = [
            record["candidate_over_control_paired_median"]
            for record in records if record["suggestion"] == suggestion
        ]
        summaries[suggestion] = {
            "cells": len(ratios),
            "wins": sum(ratio < 1.0 for ratio in ratios),
            "candidate_over_control_geomean": geomean(ratios),
            "regressions_over_5_percent": sum(ratio > 1.05 for ratio in ratios),
        }
    artifact = {
        "schema": 1,
        "experiment": {
            "label": "architectural suggestion executable upper bounds",
            "rounds": args.rounds,
            "target_ms": args.target_ms,
            "build": "--release --native --fast",
            "binary_sha256": hashes,
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
                "one release/native/fast binary; setup excluded; lanes run in "
                "separate processes with alternating order; each lane calibrated "
                "to at least 110 ms; exact checksums or closed-form results checked"
            ),
        },
        "summary": summaries,
        "results": records,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(artifact, indent=2) + "\n")
    print(json.dumps(summaries, sort_keys=True))


if __name__ == "__main__":
    main()
