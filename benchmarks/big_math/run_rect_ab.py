#!/usr/bin/env python3
"""Matched full-boxed A/B for rectangular BigInt multiplication."""

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
DEFAULT_CFLAGS = (
    "-O3 -DNDEBUG -mcpu=native -falign-functions=64 "
    "-Wno-deprecated-declarations"
)
LINE = re.compile(
    r"boxed rectangular multiply (\d+) x (\d+) limbs \((\d+) iters\): "
    r"tungsten ([0-9.]+) ns, gmp ([0-9.]+) ns, gap ([0-9.]+)x"
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
        return run(command).strip() or fallback
    except (OSError, RuntimeError):
        return fallback


def percentile(values: list[float], p: float) -> float:
    ordered = sorted(values)
    position = (len(ordered) - 1) * p
    lo = math.floor(position)
    hi = math.ceil(position)
    if lo == hi:
        return ordered[lo]
    return ordered[lo] + (ordered[hi] - ordered[lo]) * (position - lo)


def iqr(values: list[float]) -> float:
    return percentile(values, 0.75) - percentile(values, 0.25)


def geomean(values: list[float]) -> float:
    return math.exp(sum(math.log(value) for value in values) / len(values))


def parse_pairs(text: str) -> list[tuple[int, int]]:
    result = []
    for piece in text.split(","):
        left, separator, right = piece.strip().lower().partition("x")
        if not separator:
            raise argparse.ArgumentTypeError(f"invalid pair: {piece!r}")
        try:
            a, b = int(left), int(right)
        except ValueError as error:
            raise argparse.ArgumentTypeError(f"invalid pair: {piece!r}") from error
        if a <= 0 or b <= 0:
            raise argparse.ArgumentTypeError("limb counts must be positive")
        result.append((a, b))
    if not result:
        raise argparse.ArgumentTypeError("at least one pair is required")
    return result


def machine(cflags: str) -> dict:
    cpu = output(["sysctl", "-n", "machdep.cpu.brand_string"], "")
    if not cpu:
        cpu = platform.processor() or "unknown"
    return {
        "machine": platform.machine(),
        "platform": platform.platform(),
        "cpu": cpu,
        "logical_cpus": os.cpu_count(),
        "load_average": list(os.getloadavg()),
        "compiler": output(["clang", "--version"]).splitlines()[0],
        "compiler_flags": cflags,
        "target_triple": output(["clang", "-dumpmachine"]),
    }


def build(binary: Path, cflags: str) -> None:
    env = os.environ.copy()
    env["BENCH_OUT"] = str(binary)
    env["CFLAGS"] = cflags
    run([str(BUILD), "--build-only"], env=env)


def sample(binary: Path, pair: tuple[int, int], iterations: int) -> dict:
    text = run([
        str(binary), "--bench-boxed-mul-rect",
        str(pair[0]), str(pair[1]), str(iterations),
    ])
    match = LINE.fullmatch(text)
    if not match:
        raise RuntimeError(f"unexpected benchmark output: {text!r}")
    return {
        "iterations": int(match.group(3)),
        "tungsten_ns": float(match.group(4)),
        "gmp_ns": float(match.group(5)),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--pairs", type=parse_pairs,
        default=parse_pairs(
            "32x96,32x128,32x256,48x144,48x192,48x384,"
            "64x128,64x192,64x256,64x512,128x256,128x384,"
            "128x512,128x1024,256x512,256x768,256x1024,"
            "256x2048,512x1536,512x2048,512x4096"
        ),
    )
    parser.add_argument("--rounds", type=int, default=9)
    parser.add_argument("--target-ms", type=float, default=110.0)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.rounds < 9 or args.target_ms < 110:
        parser.error("acceptance runs require --rounds >= 9 and --target-ms >= 110")

    base_flags = DEFAULT_CFLAGS + " -DBN_LOPSIDED_STITCH=0"
    candidate_flags = DEFAULT_CFLAGS
    names = ("zero-and-add-stitch", "overlap-copy-stitch")
    start_machine = machine(base_flags)
    samples: dict[tuple[str, tuple[int, int]], list[dict]] = {
        (name, pair): [] for name in names for pair in args.pairs
    }
    iterations: dict[tuple[int, int], int] = {}

    with tempfile.TemporaryDirectory(prefix="tungsten-rect-ab-") as temp:
        directory = Path(temp)
        binaries = {
            names[0]: directory / "baseline",
            names[1]: directory / "candidate",
        }
        print(f"Building {names[0]}...", flush=True)
        build(binaries[names[0]], base_flags)
        print(f"Building {names[1]}...", flush=True)
        build(binaries[names[1]], candidate_flags)
        hashes = {
            name: hashlib.sha256(path.read_bytes()).hexdigest()
            for name, path in binaries.items()
        }

        for pair in args.pairs:
            probe = sample(binaries[names[1]], pair, 3)
            count = int(args.target_ms * 1_000_000 / max(probe["tungsten_ns"], 0.1))
            iterations[pair] = max(3, min(count, 50_000_000))

        for round_index in range(args.rounds):
            order = list(names)
            if round_index & 1:
                order.reverse()
            print(
                f"Round {round_index + 1}/{args.rounds}: " + " then ".join(order),
                flush=True,
            )
            for name in order:
                for pair in args.pairs:
                    samples[(name, pair)].append(
                        sample(binaries[name], pair, iterations[pair]))

    results = []
    for pair in args.pairs:
        before = samples[(names[0], pair)]
        after = samples[(names[1], pair)]
        before_ns = [row["tungsten_ns"] for row in before]
        after_ns = [row["tungsten_ns"] for row in after]
        paired = [a / b for a, b in zip(after_ns, before_ns, strict=True)]
        gmp_ratios = [
            row["tungsten_ns"] / row["gmp_ns"] for row in after
        ]
        results.append({
            "short_limbs": min(pair),
            "long_limbs": max(pair),
            "ratio": max(pair) / min(pair),
            "iterations": iterations[pair],
            "baseline_ns_median": statistics.median(before_ns),
            "baseline_ns_iqr": iqr(before_ns),
            "candidate_ns_median": statistics.median(after_ns),
            "candidate_ns_iqr": iqr(after_ns),
            "candidate_over_baseline_paired_median": statistics.median(paired),
            "candidate_over_baseline_paired_iqr": iqr(paired),
            "candidate_over_gmp_median": statistics.median(gmp_ratios),
            "samples": {names[0]: before, names[1]: after},
            "paired_ratios": paired,
        })

    changed = [row for row in results if row["ratio"] > 2.0]
    ratios = [row["candidate_over_baseline_paired_median"] for row in changed]
    artifact = {
        "schema": 1,
        "suggestion": "GROK-13",
        "experiment": {
            "label": "boxed rectangular overlap stitch",
            "baseline": names[0],
            "candidate": names[1],
            "baseline_flags": base_flags,
            "candidate_flags": candidate_flags,
            "rounds": args.rounds,
            "target_ms": args.target_ms,
            "pairs": args.pairs,
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
                "same-source builds differing only in BN_LOPSIDED_STITCH; "
                "variant order alternates by round; every sample is a full boxed "
                "immutable result with one previous result live; GMP uses two "
                "alternating public-API mpz destinations and checks every pair"
            ),
        },
        "summary": {
            "changed_cells": len(changed),
            "candidate_wins": sum(value < 1 for value in ratios),
            "candidate_losses": sum(value > 1 for value in ratios),
            "candidate_over_baseline_geomean": geomean(ratios),
            "regressions_over_5_percent": sum(value > 1.05 for value in ratios),
            "control_cells": len(results) - len(changed),
        },
        "results": results,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(artifact, indent=2) + "\n")
    print(json.dumps(artifact["summary"], sort_keys=True))
    for row in results:
        print(
            f"{row['short_limbs']}x{row['long_limbs']}\t"
            f"{row['candidate_over_baseline_paired_median']:.4f}\t"
            f"{row['candidate_over_gmp_median']:.4f}"
        )


if __name__ == "__main__":
    main()
