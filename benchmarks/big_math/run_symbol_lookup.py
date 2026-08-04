#!/usr/bin/env python3
"""Measure local BigInt access, explicit Hash lookup, and user caching."""

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
SOURCE = ROOT / "benchmarks/big_math/symbol_lookup.w"
LANES = ("local", "hash", "cached")
LINE = re.compile(r"(\w+)\t(\d+)\t([0-9.]+)\t(-?\d+)")


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


def sample(path: Path, lane: str, iterations: int) -> tuple[float, int]:
    text = run([str(path), lane, str(iterations)])
    match = LINE.fullmatch(text)
    if not match or match.group(1) != lane or int(match.group(2)) != iterations:
        raise RuntimeError(f"unexpected {lane} output: {text!r}")
    return float(match.group(3)), int(match.group(4))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--rounds", type=int, default=9)
    parser.add_argument("--iterations", type=int, default=2_000_001)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.rounds < 9 or args.iterations <= 0:
        parser.error("acceptance runs require >=9 rounds and positive iterations")

    samples = {lane: [] for lane in LANES}
    checksums: dict[str, int] = {}
    start_machine = machine()
    with tempfile.TemporaryDirectory(prefix="tungsten-symbol-lookup-") as temp:
        directory = Path(temp)
        compiler = directory / "tungsten-compiler"
        binary = directory / "symbol-lookup"
        ll_path = directory / "symbol-lookup.ll"
        print("Building current compiler release/native/fast...", flush=True)
        run([
            str(ROOT / "bin/tungsten"), "-o", str(compiler),
            "--release", "--native", "--fast",
            str(ROOT / "compiler/tungsten.w"),
        ])
        env = os.environ.copy()
        env["TUNGSTEN_ROOT"] = str(ROOT)
        env["TUNGSTEN_LL_PATH"] = str(ll_path)
        print("Building symbol-lookup benchmark release/native/fast...", flush=True)
        run([
            str(compiler), "-o", str(binary),
            "--release", "--native", "--fast", str(SOURCE),
        ], env=env)
        ir = ll_path.read_text(errors="replace")
        hashes = {
            "compiler": hashlib.sha256(compiler.read_bytes()).hexdigest(),
            "binary": hashlib.sha256(binary.read_bytes()).hexdigest(),
        }
        orders = list(itertools.permutations(LANES))
        for round_index in range(args.rounds):
            order = orders[round_index % len(orders)]
            print(f"Round {round_index + 1}/{args.rounds}: " + " then ".join(order), flush=True)
            for lane in order:
                ns, checksum = sample(binary, lane, args.iterations)
                checksums.setdefault(lane, checksum)
                if checksums[lane] != checksum:
                    raise RuntimeError(f"unstable checksum for {lane}")
                samples[lane].append(ns)

    if len(set(checksums.values())) != 1:
        raise RuntimeError(f"lane checksum mismatch: {checksums}")
    medians = {lane: statistics.median(samples[lane]) for lane in LANES}
    hash_local = [h / l for h, l in zip(samples["hash"], samples["local"], strict=True)]
    cached_local = [c / l for c, l in zip(samples["cached"], samples["local"], strict=True)]
    artifact = {
        "schema": 1,
        "suggestion": "GEMMA-19",
        "experiment": {
            "label": "compiled local vs explicit hash vs cached local",
            "rounds": args.rounds,
            "iterations": args.iterations,
            "build": "--release --native --fast",
            "binary_sha256": hashes,
            "ir_hash_get_calls": len(re.findall(r"\bcall\b[^\n]*@w_hash_get\b", ir)),
        },
        "metadata": {
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "git_commit": output(["git", "rev-parse", "HEAD"]),
            "git_dirty_tracked": bool(output(["git", "status", "--short", "--untracked-files=no"])),
            "machine_start": start_machine,
            "machine_end": machine(),
            "methodology": (
                "one release/native/fast binary; separate processes per lane; "
                "six lane orders rotate; exact iteration counts and low-bit "
                "checksums match"
            ),
        },
        "summary": {
            "medians_ns": medians,
            "hash_over_local_paired_median": statistics.median(hash_local),
            "hash_over_local_paired_iqr": iqr(hash_local),
            "cached_over_local_paired_median": statistics.median(cached_local),
            "cached_over_local_paired_iqr": iqr(cached_local),
        },
        "samples_ns": samples,
        "checksums": checksums,
        "paired_ratios": {
            "hash_over_local": hash_local,
            "cached_over_local": cached_local,
        },
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(artifact, indent=2) + "\n")
    print(json.dumps(artifact["summary"], sort_keys=True))


if __name__ == "__main__":
    main()
