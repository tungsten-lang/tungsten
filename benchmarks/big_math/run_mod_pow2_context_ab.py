#!/usr/bin/env python3
"""Measure compile-time 2^k modular context against opt-out and public GMP."""

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
SOURCE = ROOT / "benchmarks/big_math/mod_pow2_context.w"
GMP_SOURCE = ROOT / "benchmarks/big_math/mod_pow2_context_gmp.c"
WIDTHS = (64, 65, 127, 128, 129, 256, 1024, 4096)
WORKLOADS = tuple(f"modpow2_{bits}" for bits in WIDTHS)
LANES = ("generic-control", "pow2-context", "gmp-tdiv-r-2exp")
LINE = re.compile(r"(modpow2_\d+)\t(\d+)\t([0-9.]+)\t(-?\d+)")


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


def build_tungsten(compiler: Path, path: Path, ll_path: Path, enabled: bool) -> None:
    env = os.environ.copy()
    env["TUNGSTEN_ROOT"] = str(ROOT)
    env["TUNGSTEN_LL_PATH"] = str(ll_path)
    env["TUNGSTEN_BIGINT_MOD_POW2"] = "1" if enabled else "0"
    run([
        str(compiler), "-o", str(path), "--release", "--native", "--fast",
        str(SOURCE),
    ], env=env)
    if not ll_path.is_file():
        raise RuntimeError(f"missing emitted LLVM IR: {ll_path}")


def build_gmp(path: Path) -> None:
    cflags = output(["pkg-config", "--cflags", "gmp"], "")
    libs = output(["pkg-config", "--libs", "gmp"], "")
    if not libs:
        raise RuntimeError("GMP is required (pkg-config gmp failed)")
    run([
        "clang", "-O3", "-mcpu=native", *cflags.split(), str(GMP_SOURCE),
        *libs.split(), "-o", str(path),
    ])


def sample(path: Path, workload: str, iterations: int) -> tuple[float, int]:
    text = run([str(path), workload, str(iterations)])
    match = LINE.fullmatch(text)
    if not match or match.group(1) != workload:
        raise RuntimeError(f"unexpected {workload} output: {text!r}")
    if int(match.group(2)) != iterations:
        raise RuntimeError(f"iteration mismatch for {workload}: {text!r}")
    return float(match.group(3)), int(match.group(4))


def call_counts(text: str) -> dict[str, int]:
    symbols = (
        "w_bigint_mod_pow2_mut", "w_bigint_mod_pow2",
        "w_bigint_mod_mut", "w_mod", "w_bit_shl",
    )
    return {
        symbol: len(re.findall(rf"\bcall\b[^\n]*@{re.escape(symbol)}\b", text))
        for symbol in symbols
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--rounds", type=int, default=9)
    parser.add_argument("--target-ms", type=float, default=80.0)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.rounds < 9 or args.target_ms < 20:
        parser.error("acceptance runs require >=9 rounds and >=20 ms samples")

    start_machine = machine()
    samples = {
        (lane, workload): [] for lane in LANES for workload in WORKLOADS
    }
    checksums: dict[str, int] = {}
    iterations: dict[str, int] = {}

    with tempfile.TemporaryDirectory(prefix="tungsten-modpow2-") as temp:
        directory = Path(temp)
        compiler = directory / "tungsten-compiler"
        binaries = {
            "generic-control": directory / "generic-control",
            "pow2-context": directory / "pow2-context",
            "gmp-tdiv-r-2exp": directory / "gmp",
        }
        ir_paths = {
            "generic-control": directory / "generic-control.ll",
            "pow2-context": directory / "pow2-context.ll",
        }

        print("Building current compiler release/native/fast...", flush=True)
        run([
            str(ROOT / "bin/tungsten"), "-o", str(compiler),
            "--release", "--native", "--fast",
            str(ROOT / "compiler/tungsten.w"),
        ])
        print("Building exact opt-out and candidate binaries...", flush=True)
        build_tungsten(
            compiler, binaries["generic-control"],
            ir_paths["generic-control"], False,
        )
        build_tungsten(
            compiler, binaries["pow2-context"],
            ir_paths["pow2-context"], True,
        )
        print("Building public-GMP twin...", flush=True)
        build_gmp(binaries["gmp-tdiv-r-2exp"])

        # Calibrate every width from the slowest lane so all three use the
        # same exact iteration count and the fastest lane still gets a long
        # enough timed region. A discarded full-count pass warms each lane.
        for workload in WORKLOADS:
            probe_ns = []
            probe_checksum = None
            for lane in LANES:
                ns, checksum = sample(binaries[lane], workload, 100_000)
                probe_ns.append(ns)
                if probe_checksum is None:
                    probe_checksum = checksum
                if probe_checksum != checksum:
                    raise RuntimeError(f"probe checksum mismatch for {workload}")
            count = int(args.target_ms * 1_000_000 / max(probe_ns))
            count = max(50_000, min(20_000_000, count))
            if count % 2 == 0:
                count += 1
            iterations[workload] = count
            warm_checksum = None
            for lane in LANES:
                _, checksum = sample(binaries[lane], workload, count)
                if warm_checksum is None:
                    warm_checksum = checksum
                if checksum != warm_checksum:
                    raise RuntimeError(f"warmup checksum mismatch for {workload}")
            checksums[workload] = warm_checksum

        orders = list(itertools.permutations(LANES))
        for round_index in range(args.rounds):
            order = orders[round_index % len(orders)]
            workloads = WORKLOADS[round_index % len(WORKLOADS):] + WORKLOADS[:round_index % len(WORKLOADS)]
            print(
                f"Round {round_index + 1}/{args.rounds}: " + " then ".join(order),
                flush=True,
            )
            for workload in workloads:
                for lane in order:
                    ns, checksum = sample(
                        binaries[lane], workload, iterations[workload]
                    )
                    if checksum != checksums[workload]:
                        raise RuntimeError(f"checksum mismatch for {workload}")
                    samples[(lane, workload)].append(ns)

        ir_text = {
            name: path.read_text(errors="replace")
            for name, path in ir_paths.items()
        }
        hashes = {
            "compiler": sha256(compiler),
            **{name: sha256(path) for name, path in binaries.items()},
        }

    results = []
    for workload in WORKLOADS:
        control = samples[("generic-control", workload)]
        candidate = samples[("pow2-context", workload)]
        gmp = samples[("gmp-tdiv-r-2exp", workload)]
        over_control = [
            c / b for c, b in zip(candidate, control, strict=True)
        ]
        over_gmp = [c / g for c, g in zip(candidate, gmp, strict=True)]
        results.append({
            "workload": workload,
            "iterations": iterations[workload],
            "checksum": checksums[workload],
            "control_ns_median": statistics.median(control),
            "control_ns_iqr": iqr(control),
            "candidate_ns_median": statistics.median(candidate),
            "candidate_ns_iqr": iqr(candidate),
            "gmp_ns_median": statistics.median(gmp),
            "gmp_ns_iqr": iqr(gmp),
            "candidate_over_control_paired_median": statistics.median(over_control),
            "candidate_over_control_paired_iqr": iqr(over_control),
            "candidate_over_gmp_paired_median": statistics.median(over_gmp),
            "candidate_over_gmp_paired_iqr": iqr(over_gmp),
            "samples_ns": {
                "generic-control": control,
                "pow2-context": candidate,
                "gmp-tdiv-r-2exp": gmp,
            },
            "paired_ratios": {
                "candidate_over_control": over_control,
                "candidate_over_gmp": over_gmp,
            },
        })

    control_ratios = [
        row["candidate_over_control_paired_median"] for row in results
    ]
    gmp_ratios = [row["candidate_over_gmp_paired_median"] for row in results]
    artifact = {
        "schema": 1,
        "suggestions": ["GEMMA-14"],
        "experiment": {
            "label": "compile-time power-of-two modular context",
            "rounds": args.rounds,
            "target_ms": args.target_ms,
            "build": "--release --native --fast",
            "build_modes": {
                "generic-control": {"TUNGSTEN_BIGINT_MOD_POW2": 0},
                "pow2-context": {"TUNGSTEN_BIGINT_MOD_POW2": 1},
            },
            "source_sha256": {
                str(SOURCE.relative_to(ROOT)): sha256(SOURCE),
                str(GMP_SOURCE.relative_to(ROOT)): sha256(GMP_SOURCE),
            },
            "binary_sha256": hashes,
            "ir_call_counts": {
                name: call_counts(text) for name, text in ir_text.items()
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
                "identical Tungsten source compiled release/native/fast with "
                "only literal 2^k context disabled/enabled; public GMP twin "
                "reuses mpz destinations and calls mpz_tdiv_r_2exp; exact "
                "per-width iteration counts and checksums match; six lane "
                "orders and rotating width order reduce drift"
            ),
        },
        "summary": {
            "cells": len(results),
            "candidate_control_wins": sum(v < 1 for v in control_ratios),
            "candidate_control_losses": sum(v > 1 for v in control_ratios),
            "candidate_over_control_geomean": math.exp(
                sum(math.log(v) for v in control_ratios) / len(control_ratios)
            ),
            "control_regressions_over_5_percent": sum(
                v > 1.05 for v in control_ratios
            ),
            "candidate_gmp_wins": sum(v < 1 for v in gmp_ratios),
            "candidate_gmp_losses": sum(v > 1 for v in gmp_ratios),
            "candidate_over_gmp_geomean": math.exp(
                sum(math.log(v) for v in gmp_ratios) / len(gmp_ratios)
            ),
        },
        "results": results,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(artifact, indent=2) + "\n")
    print(json.dumps(artifact["summary"], sort_keys=True))
    for row in results:
        print(
            f"{row['workload']}\t{row['control_ns_median']:.3f}\t"
            f"{row['candidate_ns_median']:.3f}\t{row['gmp_ns_median']:.3f}\t"
            f"{row['candidate_over_control_paired_median']:.4f}\t"
            f"{row['candidate_over_gmp_paired_median']:.4f}"
        )


if __name__ == "__main__":
    main()
