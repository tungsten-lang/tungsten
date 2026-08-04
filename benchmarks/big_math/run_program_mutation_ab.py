#!/usr/bin/env python3
"""Measure release/native/fast BigInt loops with mutation enabled/disabled."""

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
SOURCE = ROOT / "benchmarks/big_math/program_loops.w"
GMP_SOURCE = ROOT / "benchmarks/big_math/program_loops_gmp.c"
WORKLOADS = ("accumulate", "mulchain", "addchain", "subchain", "divchain")
MOD_WORKLOADS = tuple(f"modchain{limbs}" for limbs in (2, 4, 8, 16, 32, 65, 128))
SQR_WORKLOADS = tuple(f"sqrchain{limbs}" for limbs in (2, 4, 8, 16, 32, 65, 128))
LINE = re.compile(r"(\w+)\t(\d+)\t([0-9.]+)\t(-?\d+)")


def run(
    command: list[str], *, env: dict[str, str] | None = None
) -> subprocess.CompletedProcess[str]:
    completed = subprocess.run(
        command, cwd=ROOT, env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    if completed.returncode:
        detail = completed.stderr.strip() or completed.stdout.strip()
        raise RuntimeError(f"command failed: {' '.join(command)}\n{detail}")
    return completed


def output(command: list[str], fallback: str = "unknown") -> str:
    try:
        return run(command).stdout.strip() or fallback
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


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


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


def build_tungsten(
    compiler: Path, path: Path, *, mutate: bool, mod_mut: bool = True,
    sqr_mut: bool = True,
) -> Path:
    env = os.environ.copy()
    env["TUNGSTEN_ROOT"] = str(ROOT)
    env["TUNGSTEN_BIGINT_MUTATE_UNIQUE"] = "1" if mutate else "0"
    env["TUNGSTEN_BIGINT_MOD_MUT"] = "1" if mod_mut else "0"
    env["TUNGSTEN_BIGINT_SQR_MUT"] = "1" if sqr_mut else "0"
    ll_path = path.with_suffix(".ll")
    env["TUNGSTEN_LL_PATH"] = str(ll_path)
    run([
        str(compiler), "-o", str(path),
        "--release", "--native", "--fast", str(SOURCE),
    ], env=env)
    if not ll_path.is_file():
        raise RuntimeError(f"compiler did not retain requested LLVM IR: {ll_path}")
    return ll_path


def build_gmp(path: Path) -> None:
    cflags = output(["pkg-config", "--cflags", "gmp"], "")
    libs = output(["pkg-config", "--libs", "gmp"], "")
    if not libs:
        raise RuntimeError("GMP is required (pkg-config gmp failed)")
    run([
        "clang", "-O3", "-mcpu=native", *cflags.split(), str(GMP_SOURCE),
        *libs.split(), "-o", str(path),
    ])


def sample(path: Path, workload: str) -> tuple[int, float, int]:
    if workload.startswith("modchain") or workload.startswith("sqrchain"):
        base = "modchain" if workload.startswith("modchain") else "sqrchain"
        limbs = workload.removeprefix(base)
        text = run([str(path), base, "2000000", limbs]).stdout.strip()
    else:
        text = run([str(path), workload]).stdout.strip()
    match = LINE.fullmatch(text)
    if not match or match.group(1) != workload:
        raise RuntimeError(f"unexpected {workload} output: {text!r}")
    return int(match.group(2)), float(match.group(3)), int(match.group(4))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--rounds", type=int, default=9)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--feature", choices=("all", "mod", "sqr"), default="all")
    args = parser.parse_args()
    if args.rounds < 9:
        parser.error("acceptance runs require --rounds >= 9")

    if args.feature == "mod":
        workloads = MOD_WORKLOADS
        lanes = ("immutable-mod", "mutating-mod", "gmp-destination")
        build_modes = ((True, False, True), (True, True, True))
    elif args.feature == "sqr":
        workloads = SQR_WORKLOADS
        lanes = ("immutable-sqr", "mutating-sqr", "gmp-destination")
        build_modes = ((True, True, False), (True, True, True))
    else:
        workloads = WORKLOADS
        lanes = ("immutable-churn", "mutate-if-unique", "gmp-destination")
        build_modes = ((False, True, True), (True, True, True))
    samples = {
        (lane, workload): [] for lane in lanes for workload in workloads
    }
    iterations: dict[str, int] = {}
    checksums: dict[str, int] = {}
    start_machine = machine()

    with tempfile.TemporaryDirectory(prefix="tungsten-mut-ab-") as temp:
        directory = Path(temp)
        compiler = directory / "tungsten-compiler"
        print("Building current compiler release/native/fast...", flush=True)
        run([
            str(ROOT / "bin/tungsten"), "-o", str(compiler),
            "--release", "--native", "--fast",
            str(ROOT / "compiler/tungsten.w"),
        ])
        binaries = {
            lanes[0]: directory / "immutable",
            lanes[1]: directory / "mutating",
            "gmp-destination": directory / "gmp",
        }
        print(f"Building {lanes[0]} release/native/fast...", flush=True)
        ir_paths = {}
        ir_paths[lanes[0]] = build_tungsten(
            compiler, binaries[lanes[0]],
            mutate=build_modes[0][0], mod_mut=build_modes[0][1],
            sqr_mut=build_modes[0][2],
        )
        print(f"Building {lanes[1]} release/native/fast...", flush=True)
        ir_paths[lanes[1]] = build_tungsten(
            compiler, binaries[lanes[1]],
            mutate=build_modes[1][0], mod_mut=build_modes[1][1],
            sqr_mut=build_modes[1][2],
        )
        print("Building GMP destination-reuse twin...", flush=True)
        build_gmp(binaries["gmp-destination"])
        compiler_hash = sha256(compiler)
        hashes = {name: sha256(path) for name, path in binaries.items()}
        ir_text = {
            name: path.read_text(errors="replace")
            for name, path in ir_paths.items()
        }

        orders = list(itertools.permutations(lanes))
        for round_index in range(args.rounds):
            order = orders[round_index % len(orders)]
            print(
                f"Round {round_index + 1}/{args.rounds}: " + " then ".join(order),
                flush=True,
            )
            for lane in order:
                for workload in workloads:
                    count, ns, checksum = sample(binaries[lane], workload)
                    previous_count = iterations.setdefault(workload, count)
                    if previous_count != count:
                        raise RuntimeError(f"iteration mismatch for {workload}")
                    previous_checksum = checksums.setdefault(workload, checksum)
                    if previous_checksum != checksum:
                        raise RuntimeError(f"checksum mismatch for {workload}")
                    samples[(lane, workload)].append(ns)

    results = []
    for workload in workloads:
        before = samples[(lanes[0], workload)]
        after = samples[(lanes[1], workload)]
        gmp = samples[(lanes[2], workload)]
        paired = [a / b for a, b in zip(after, before, strict=True)]
        versus_gmp = [a / g for a, g in zip(after, gmp, strict=True)]
        results.append({
            "workload": workload,
            "iterations": iterations[workload],
            "checksum": checksums[workload],
            "immutable_ns_median": statistics.median(before),
            "immutable_ns_iqr": iqr(before),
            "mutating_ns_median": statistics.median(after),
            "mutating_ns_iqr": iqr(after),
            "gmp_ns_median": statistics.median(gmp),
            "gmp_ns_iqr": iqr(gmp),
            "mutating_over_immutable_paired_median": statistics.median(paired),
            "mutating_over_immutable_paired_iqr": iqr(paired),
            "mutating_over_gmp_paired_median": statistics.median(versus_gmp),
            "mutating_over_gmp_paired_iqr": iqr(versus_gmp),
            "samples": {
                lanes[0]: before, lanes[1]: after, lanes[2]: gmp,
            },
            "paired_ratios": paired,
            "paired_gmp_ratios": versus_gmp,
        })
    ratios = [row["mutating_over_immutable_paired_median"] for row in results]
    artifact = {
        "schema": 1,
        "suggestion": "GLM-01",
        "experiment": {
            "label": "whole-language mutate-if-unique " + args.feature,
            "rounds": args.rounds,
            "build": "--release --native --fast",
            "feature": args.feature,
            "build_modes": {
                lanes[0]: {
                    "TUNGSTEN_BIGINT_MUTATE_UNIQUE": int(build_modes[0][0]),
                    "TUNGSTEN_BIGINT_MOD_MUT": int(build_modes[0][1]),
                    "TUNGSTEN_BIGINT_SQR_MUT": int(build_modes[0][2]),
                },
                lanes[1]: {
                    "TUNGSTEN_BIGINT_MUTATE_UNIQUE": int(build_modes[1][0]),
                    "TUNGSTEN_BIGINT_MOD_MUT": int(build_modes[1][1]),
                    "TUNGSTEN_BIGINT_SQR_MUT": int(build_modes[1][2]),
                },
            },
            "compiler_sha256": compiler_hash,
            "binary_sha256": hashes,
            "mutating_call_counts": {
                name: {
                    symbol: len(re.findall(
                        rf"\bcall\b[^\n]*@{re.escape(symbol)}\b", text
                    ))
                    for symbol in (
                        "w_bigint_add_mut", "w_bigint_sub_mut",
                        "w_bigint_mul_mut", "w_bigint_div_mut",
                        "w_bigint_mod_mut",
                        "w_bigint_add_dest",
                    )
                }
                for name, text in ir_text.items()
            },
        },
        "metadata": {
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "git_commit": output(["git", "rev-parse", "HEAD"]),
            "git_dirty_tracked": bool(output([
                "git", "status", "--short", "--untracked-files=no"
            ])),
            "gmp_version": output(["pkg-config", "--modversion", "gmp"]),
            "machine_start": start_machine,
            "machine_end": machine(),
            "methodology": (
                "same Tungsten source compiled release/native/fast with only "
                "the selected consumed-destination feature disabled/enabled; "
                "GMP uses idiomatic retained destinations; all lanes share "
                "exact iteration counts and checksums; six lane orders rotate"
            ),
        },
        "summary": {
            "cells": len(results),
            "candidate_wins": sum(value < 1 for value in ratios),
            "candidate_losses": sum(value > 1 for value in ratios),
            "candidate_over_control_geomean": math.exp(
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
            f"{row['workload']}\t{row['immutable_ns_median']:.3f}\t"
            f"{row['mutating_ns_median']:.3f}\t"
            f"{row['mutating_over_immutable_paired_median']:.4f}\t"
            f"{row['mutating_over_gmp_paired_median']:.4f}"
        )


if __name__ == "__main__":
    main()
