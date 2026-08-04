#!/usr/bin/env python3
"""Matched release/native/fast A/B for BigInt addmul/submul lowering."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import math
import os
import platform
import statistics
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "benchmarks/big_math/linear_word_loops.w"


def run(cmd: list[str], *, env: dict[str, str] | None = None) -> str:
    return subprocess.check_output(cmd, cwd=ROOT, env=env, text=True).strip()


def percentile(values: list[float], p: float) -> float:
    xs = sorted(values)
    pos = (len(xs) - 1) * p
    lo = int(math.floor(pos))
    hi = int(math.ceil(pos))
    if lo == hi:
        return xs[lo]
    return xs[lo] + (xs[hi] - xs[lo]) * (pos - lo)


def sample(binary: Path, operation: str, limbs: int, iterations: int) -> dict:
    fields = run([str(binary), operation, str(limbs), str(iterations)]).split("\t")
    if len(fields) != 5:
        raise RuntimeError(f"unexpected benchmark output: {fields!r}")
    return {
        "operation": fields[0],
        "limbs": int(fields[1]),
        "iterations": int(fields[2]),
        "ns": float(fields[3]),
        "checksum": fields[4],
    }


def build(binary: Path, enabled: bool) -> None:
    env = os.environ.copy()
    env["TUNGSTEN_BIGINT_ADDMUL_FUSION"] = "1" if enabled else "0"
    subprocess.run(
        [str(ROOT / "bin/tungsten"), "compile", str(SOURCE), "--out", str(binary),
         "--release", "--native", "--fast"],
        cwd=ROOT, env=env, check=True, stdout=subprocess.DEVNULL,
    )


def machine_metadata() -> dict:
    cpu = "unknown"
    try:
        cpu = run(["sysctl", "-n", "machdep.cpu.brand_string"])
    except (FileNotFoundError, subprocess.CalledProcessError):
        pass
    return {
        "cpu": cpu,
        "platform": platform.platform(),
        "machine": platform.machine(),
        "logical_cpus": os.cpu_count(),
        "load_average": list(os.getloadavg()),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--rounds", type=int, default=9)
    parser.add_argument("--target-ms", type=float, default=110.0)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.rounds < 3 or args.target_ms <= 0:
        parser.error("rounds must be >=3 and target-ms must be positive")

    start_machine = machine_metadata()
    with tempfile.TemporaryDirectory(prefix="tungsten-linear-word-") as tmp:
        tmpdir = Path(tmp)
        baseline = tmpdir / "baseline"
        candidate = tmpdir / "candidate"
        build(baseline, False)
        build(candidate, True)
        binaries = {"fusion-disabled": baseline, "fusion-enabled": candidate}
        hashes = {
            name: hashlib.sha256(path.read_bytes()).hexdigest()
            for name, path in binaries.items()
        }

        results = []
        for operation in ("addmul", "submul"):
            for limbs in (1, 16, 256):
                probe = sample(candidate, operation, limbs, 2000)
                iterations = int(args.target_ms * 1_000_000 / max(probe["ns"], 0.01))
                iterations = max(2000, min(iterations, 10_000_000))
                samples = {name: [] for name in binaries}
                checksums = {}
                paired = []
                for round_index in range(args.rounds):
                    order = list(binaries)
                    if round_index % 2:
                        order.reverse()
                    round_values = {}
                    for name in order:
                        row = sample(binaries[name], operation, limbs, iterations)
                        samples[name].append(row["ns"])
                        round_values[name] = row["ns"]
                        previous = checksums.setdefault(name, row["checksum"])
                        if previous != row["checksum"]:
                            raise RuntimeError(f"nondeterministic checksum for {name} {operation}{limbs}")
                    if checksums["fusion-disabled"] != checksums["fusion-enabled"]:
                        raise RuntimeError(f"checksum mismatch for {operation}{limbs}")
                    paired.append(round_values["fusion-enabled"] /
                                  round_values["fusion-disabled"])
                b = samples["fusion-disabled"]
                c = samples["fusion-enabled"]
                results.append({
                    "operation": operation,
                    "limbs": limbs,
                    "iterations": iterations,
                    "checksum": checksums["fusion-enabled"],
                    "baseline_ns_median": statistics.median(b),
                    "baseline_ns_iqr": percentile(b, 0.75) - percentile(b, 0.25),
                    "candidate_ns_median": statistics.median(c),
                    "candidate_ns_iqr": percentile(c, 0.75) - percentile(c, 0.25),
                    "candidate_over_baseline_paired_median": statistics.median(paired),
                    "candidate_over_baseline_paired_iqr": (
                        percentile(paired, 0.75) - percentile(paired, 0.25)),
                    "samples": samples,
                    "paired_ratios": paired,
                })

    ratios = [r["candidate_over_baseline_paired_median"] for r in results]
    output = {
        "schema": 1,
        "experiment": "compiler fused r +/-= x * word",
        "suggestion": "GLM-12",
        "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "git_head": run(["git", "rev-parse", "HEAD"]),
        "git_dirty_tracked": bool(run(["git", "status", "--short", "--untracked-files=no"])),
        "build": {
            "flags": ["--release", "--native", "--fast"],
            "baseline_env": {"TUNGSTEN_BIGINT_ADDMUL_FUSION": "0"},
            "candidate_env": {"TUNGSTEN_BIGINT_ADDMUL_FUSION": "1"},
            "binary_sha256": hashes,
        },
        "machine_start": start_machine,
        "machine_end": machine_metadata(),
        "methodology": (
            "same source and runtime; compiler fusion toggled only at lowering; "
            "variant order alternates within each outer round; timings are whole "
            "compiled Tungsten loops and checksums must match"
        ),
        "summary": {
            "cells": len(results),
            "candidate_wins": sum(r < 1 for r in ratios),
            "candidate_losses": sum(r > 1 for r in ratios),
            "candidate_over_baseline_geomean": math.exp(
                sum(math.log(r) for r in ratios) / len(ratios)),
            "regressions_over_5_percent": sum(r > 1.05 for r in ratios),
        },
        "results": results,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, indent=2) + "\n")
    print(json.dumps(output["summary"], sort_keys=True))
    for row in results:
        print(f"{row['operation']}\t{row['limbs']}\t"
              f"{row['baseline_ns_median']:.3f}\t{row['candidate_ns_median']:.3f}\t"
              f"{row['candidate_over_baseline_paired_median']:.4f}")


if __name__ == "__main__":
    main()
