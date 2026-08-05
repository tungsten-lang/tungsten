#!/usr/bin/env python3
"""Accurately remeasure every near-parity cell from a fast matrix screen."""

from __future__ import annotations

import argparse
import json
import math
import os
import platform
import subprocess
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / "benchmarks/big_math/run.sh"
NATIVE = ROOT / "benchmarks/big_math/bench_big_math"


def output(command: list[str], default: str = "unknown") -> str:
    try:
        return subprocess.check_output(
            command, cwd=ROOT, text=True, stderr=subprocess.DEVNULL
        ).strip()
    except (OSError, subprocess.CalledProcessError):
        return default


def iqr_ratio(row: dict[str, object]) -> float:
    tungsten = float(row["tungsten_ns"])
    gmp = float(row["gmp_ns"])
    return math.sqrt(
        (float(row["tungsten_iqr_ns"]) / max(tungsten, 1e-30)) ** 2
        + (float(row["gmp_iqr_ns"]) / max(gmp, 1e-30)) ** 2
    )


def sweep(operation: str, sizes: list[int], runs: int, target_ms: float) -> list[dict[str, object]]:
    command = [
        str(NATIVE), "--bench-boxed-sweep", operation,
        ",".join(str(size) for size in sizes), str(runs), f"{target_ms:g}",
    ]
    process = subprocess.run(
        command, cwd=ROOT, text=True, capture_output=True, check=True
    )
    records = []
    for line in process.stdout.splitlines():
        fields = line.split("\t")
        if len(fields) != 8 or fields[0] != "boxed" or fields[1] != operation:
            raise RuntimeError(f"unexpected sweep row: {line!r}")
        tungsten_ns = float(fields[4])
        gmp_ns = float(fields[5])
        record: dict[str, object] = {
            "operation": operation,
            "limbs": int(fields[2]),
            "iterations": int(fields[3]),
            "tungsten_ns": tungsten_ns,
            "gmp_ns": gmp_ns,
            "tungsten_iqr_ns": float(fields[6]),
            "gmp_iqr_ns": float(fields[7]),
            "tungsten_over_gmp": tungsten_ns / gmp_ns,
            "selection": "best_iqr",
        }
        record["relative_iqr"] = iqr_ratio(record)
        records.append(record)
    if [int(record["limbs"]) for record in records] != sizes:
        raise RuntimeError(
            f"sweep row mismatch for {operation}: expected {sizes}, "
            f"got {[record['limbs'] for record in records]}"
        )
    return records


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--screen", type=Path, required=True)
    parser.add_argument("--threshold", type=float, default=0.95)
    parser.add_argument("--runs", type=int, default=9)
    parser.add_argument("--target-ms", type=float, default=110.0)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if not 0.0 < args.threshold <= 1.0:
        parser.error("--threshold must be in (0, 1]")
    if args.runs < 9 or args.target_ms < 110.0:
        parser.error("acceptance runs require >=9 runs and >=110 ms")

    screen = json.loads(args.screen.read_text())
    cells: dict[str, list[tuple[int, float]]] = defaultdict(list)
    screen_rows = screen.get("results", screen.get("records"))
    if screen_rows is None:
        raise RuntimeError("screen must contain results or records")
    for row in screen_rows:
        ratio = float(row["tungsten_over_gmp"])
        limbs = int(row["limbs"])
        if ratio >= args.threshold:
            if limbs > 8192:
                raise RuntimeError("default residual matrix must stop at 8192 limbs")
            cells[str(row["operation"])].append((limbs, ratio))
    if not cells:
        raise RuntimeError("screen has no cells at or above the threshold")

    subprocess.run([str(BUILD), "--build-only"], cwd=ROOT, check=True)
    records = []
    for operation, selected in cells.items():
        sizes = [limbs for limbs, _ratio in selected]
        screen_ratios = {limbs: ratio for limbs, ratio in selected}
        for record in sweep(operation, sizes, args.runs, args.target_ms):
            record["screen_ratio"] = screen_ratios[int(record["limbs"])]
            records.append(record)
            print(
                f"{operation:7s}@{int(record['limbs']):5d} "
                f"screen={float(record['screen_ratio']):.3f} "
                f"accurate={float(record['tungsten_over_gmp']):.3f} "
                f"relative_iqr={float(record['relative_iqr']):.3f}",
                flush=True,
            )

    payload = {
        "schema": "tungsten.bigint.residual-matrix/v1",
        "metadata": {
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "git_commit": output(["git", "rev-parse", "HEAD"]),
            "git_dirty_tracked": bool(
                output(["git", "status", "--porcelain", "--untracked-files=no"], "")
            ),
            "screen": str(args.screen),
            "screen_sha256": output(["shasum", "-a", "256", str(args.screen)]).split()[0],
            "threshold": args.threshold,
            "runs": args.runs,
            "target_ms": args.target_ms,
            "selection": "best elapsed time with IQR retained, matching the default <=8192-limb matrix",
            "machine": {
                "hostname": platform.node(),
                "platform": platform.platform(),
                "machine": platform.machine(),
                "logical_cpus": os.cpu_count(),
                "target_triple": output(["clang", "-dumpmachine"]),
                "clang": output(["clang", "--version"]).splitlines()[0],
                "gmp_version": output(["pkg-config", "--modversion", "gmp"]),
                "power": output(["pmset", "-g", "batt"]),
                "load_average": list(os.getloadavg()),
            },
        },
        "records": records,
        "summary": {
            "screen_cells": len(records),
            "accurate_wins": sum(
                float(record["tungsten_over_gmp"]) < 1.0 for record in records
            ),
            "accurate_losses": sum(
                float(record["tungsten_over_gmp"]) >= 1.0 for record in records
            ),
        },
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, indent=2) + "\n")
    print(f"Wrote {args.output}")


if __name__ == "__main__":
    main()
