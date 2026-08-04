#!/usr/bin/env python3
"""Matched A/B for the u64 primality candidate prefilter."""

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
FLAGS = "-O3 -DNDEBUG -mcpu=native -falign-functions=64 -Wno-deprecated-declarations"
LINE = re.compile(r"prime prefilter (easy|mixed|prime) \((\d+) iters\): tungsten ([0-9.]+) ns")
MODES = ("easy", "mixed", "prime")


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


def percentile(values: list[float], p: float) -> float:
    ordered = sorted(values)
    position = (len(ordered) - 1) * p
    lo, hi = math.floor(position), math.ceil(position)
    if lo == hi:
        return ordered[lo]
    return ordered[lo] + (ordered[hi] - ordered[lo]) * (position - lo)


def iqr(values: list[float]) -> float:
    return percentile(values, 0.75) - percentile(values, 0.25)


def machine(flags: str) -> dict:
    cpu = output(["sysctl", "-n", "machdep.cpu.brand_string"], "")
    return {
        "cpu": cpu or platform.processor() or "unknown",
        "machine": platform.machine(),
        "platform": platform.platform(),
        "logical_cpus": os.cpu_count(),
        "load_average": list(os.getloadavg()),
        "compiler": output(["clang", "--version"]).splitlines()[0],
        "compiler_flags": flags,
        "target_triple": output(["clang", "-dumpmachine"]),
    }


def build(binary: Path, flags: str) -> None:
    env = os.environ.copy()
    env["BENCH_OUT"] = str(binary)
    env["CFLAGS"] = flags
    run([str(BUILD), "--build-only"], env=env)


def sample(binary: Path, mode: str, iterations: int) -> float:
    text = run([
        str(binary), "--bench-prime-prefilter", mode, str(iterations),
    ])
    match = LINE.fullmatch(text)
    if not match or match.group(1) != mode or int(match.group(2)) != iterations:
        raise RuntimeError(f"unexpected benchmark output: {text!r}")
    return float(match.group(3))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--rounds", type=int, default=9)
    parser.add_argument("--target-ms", type=float, default=110.0)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.rounds < 9 or args.target_ms < 110:
        parser.error("acceptance runs require --rounds >= 9 and --target-ms >= 110")

    baseline_flags = FLAGS + " -DBN_PRIME_PREFILTER=0"
    candidate_flags = FLAGS
    names = ("seven-base-no-prefilter", "tiered-prefilter")
    samples = {(name, mode): [] for name in names for mode in MODES}
    iterations = {}
    start_machine = machine(baseline_flags)

    with tempfile.TemporaryDirectory(prefix="tungsten-prime-prefilter-") as temp:
        directory = Path(temp)
        binaries = {names[0]: directory / "baseline", names[1]: directory / "candidate"}
        print(f"Building {names[0]}...", flush=True)
        build(binaries[names[0]], baseline_flags)
        print(f"Building {names[1]}...", flush=True)
        build(binaries[names[1]], candidate_flags)
        hashes = {
            name: hashlib.sha256(path.read_bytes()).hexdigest()
            for name, path in binaries.items()
        }
        for mode in MODES:
            probe = sample(binaries[names[1]], mode, 1000)
            count = int(args.target_ms * 1_000_000 / max(probe, 0.1))
            iterations[mode] = max(1000, min(count, 100_000_000))

        for round_index in range(args.rounds):
            order = list(names)
            if round_index & 1:
                order.reverse()
            print(
                f"Round {round_index + 1}/{args.rounds}: " + " then ".join(order),
                flush=True,
            )
            for name in order:
                for mode in MODES:
                    samples[(name, mode)].append(
                        sample(binaries[name], mode, iterations[mode]))

    results = []
    for mode in MODES:
        before = samples[(names[0], mode)]
        after = samples[(names[1], mode)]
        paired = [a / b for a, b in zip(after, before, strict=True)]
        results.append({
            "mode": mode,
            "iterations": iterations[mode],
            "baseline_ns_median": statistics.median(before),
            "baseline_ns_iqr": iqr(before),
            "candidate_ns_median": statistics.median(after),
            "candidate_ns_iqr": iqr(after),
            "candidate_over_baseline_paired_median": statistics.median(paired),
            "candidate_over_baseline_paired_iqr": iqr(paired),
            "samples": {names[0]: before, names[1]: after},
            "paired_ratios": paired,
        })
    ratios = [row["candidate_over_baseline_paired_median"] for row in results]
    artifact = {
        "schema": 1,
        "suggestion": "GEMMA-06",
        "experiment": {
            "label": "u64 primality prefilter",
            "baseline": names[0],
            "candidate": names[1],
            "baseline_flags": baseline_flags,
            "candidate_flags": candidate_flags,
            "rounds": args.rounds,
            "target_ms": args.target_ms,
            "binary_sha256": hashes,
        },
        "metadata": {
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "git_commit": output(["git", "rev-parse", "HEAD"]),
            "git_dirty_tracked": bool(output([
                "git", "status", "--short", "--untracked-files=no"
            ])),
            "gmp_version": output(["pkg-config", "--modversion", "gmp"]),
            "machine_start": start_machine,
            "machine_end": machine(candidate_flags),
            "methodology": (
                "same-source builds differ only in BN_PRIME_PREFILTER; fixtures "
                "are deterministic large easy composites, GMP-generated large "
                "primes, and a 50/50 mix; every value is checked with public "
                "mpz_probab_prime_p before timing; variant order alternates"
            ),
        },
        "summary": {
            "cells": len(results),
            "candidate_wins": sum(value < 1 for value in ratios),
            "candidate_losses": sum(value > 1 for value in ratios),
            "candidate_over_baseline_geomean": math.exp(
                sum(math.log(value) for value in ratios) / len(ratios)
            ),
            "regressions_over_5_percent": sum(value > 1.05 for value in ratios),
        },
        "results": results,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(artifact, indent=2) + "\n")
    print(json.dumps(artifact["summary"], sort_keys=True))
    for row in results:
        print(
            f"{row['mode']}\t{row['baseline_ns_median']:.3f}\t"
            f"{row['candidate_ns_median']:.3f}\t"
            f"{row['candidate_over_baseline_paired_median']:.4f}"
        )


if __name__ == "__main__":
    main()
