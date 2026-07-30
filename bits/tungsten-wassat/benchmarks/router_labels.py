#!/usr/bin/env python3
"""Derive paired marginal routing labels from router_dataset.py JSONL.

The output CSV is intentionally small and model-facing:

  instance_sha256,family_id,split,label,utility,weight,<ordered features...>

`label=1` means the treatment policy should replace the baseline for that
instance.  Ties conservatively retain the baseline.  `utility` is paired
baseline PAR-2 minus treatment PAR-2, so positive is better; `weight` preserves
large solve/timeout changes without allowing one row to dominate arbitrarily.
Runs must use the collector's isolated environment contract and one exact
solver SHA; select it explicitly when a resumable JSONL contains several builds.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import statistics
from collections import defaultdict
from pathlib import Path

import router_dataset as DATASET


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dataset", type=Path)
    parser.add_argument("--baseline", required=True)
    parser.add_argument("--treatment", required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument(
        "--solver-sha256",
        help="select one solver binary when the JSONL contains multiple builds",
    )
    parser.add_argument("--ratio", type=float, default=0.95)
    parser.add_argument("--min-seconds", type=float, default=0.05)
    args = parser.parse_args()
    if not (0 < args.ratio <= 1) or args.min_seconds < 0:
        parser.error("ratio must be in (0,1] and min-seconds must be nonnegative")
    if args.baseline == args.treatment:
        parser.error("baseline and treatment must differ")
    if args.solver_sha256 is not None and not re.fullmatch(
        r"[0-9a-f]{64}", args.solver_sha256
    ):
        parser.error("solver-sha256 must be 64 lowercase hexadecimal characters")

    instances: dict[str, dict] = {}
    raw_runs = []
    available_solvers: set[str] = set()
    with args.dataset.open() as stream:
        for line in stream:
            record = json.loads(line)
            kind = record.get("record_type")
            if kind == "instance":
                if record.get("feature_names") != DATASET.FEATURE_NAMES:
                    raise SystemExit(
                        "dataset feature ABI does not match router_dataset.py; "
                        "recollect before training"
                    )
                if record["instance_sha256"] in instances:
                    raise SystemExit(
                        "duplicate instance record for "
                        + record["instance_sha256"]
                    )
                instances[record["instance_sha256"]] = record
            elif kind == "run" and record.get("policy_id") in (
                args.baseline,
                args.treatment,
            ):
                solver_sha = record.get("solver_sha256")
                if not isinstance(solver_sha, str) or not re.fullmatch(
                    r"[0-9a-f]{64}", solver_sha
                ):
                    raise SystemExit("run record has invalid or missing solver_sha256")
                available_solvers.add(solver_sha)
                raw_runs.append(record)

    if not available_solvers:
        raise SystemExit("dataset contains no runs for the requested policies")
    selected_solver = args.solver_sha256
    if selected_solver is None:
        if len(available_solvers) != 1:
            choices = ", ".join(sorted(available_solvers))
            raise SystemExit(
                "dataset contains multiple solver binaries; select one with "
                f"--solver-sha256 ({choices})"
            )
        selected_solver = next(iter(available_solvers))
    elif selected_solver not in available_solvers:
        raise SystemExit("selected solver-sha256 has no requested policy runs")

    runs: dict[tuple[str, str], dict[int, dict]] = defaultdict(dict)
    for record in raw_runs:
        if record["solver_sha256"] != selected_solver:
            continue
        if record.get("environment_contract") != "ambient-wassat-stripped-v1":
            raise SystemExit(
                "selected run predates the isolated policy-environment contract; "
                "recollect before training"
            )
        key = (record["instance_sha256"], record["policy_id"])
        repetition = record["repetition"]
        if repetition in runs[key]:
            raise SystemExit(
                "duplicate run record for "
                f"{record['instance_sha256']} {record['policy_id']} rep{repetition}"
            )
        runs[key][repetition] = record

    rows = []
    skipped = 0
    for instance_sha, instance in sorted(instances.items()):
        baseline = runs.get((instance_sha, args.baseline), {})
        treatment = runs.get((instance_sha, args.treatment), {})
        repetitions = sorted(set(baseline) & set(treatment))
        if not repetitions:
            skipped += 1
            continue
        paired = [(baseline[rep], treatment[rep]) for rep in repetitions]
        if any(
            left["timeout_seconds"] != right["timeout_seconds"]
            for left, right in paired
        ):
            raise SystemExit(f"timeout mismatch for {instance_sha}")
        if any(
            left.get("machine") != right.get("machine")
            for left, right in paired
        ):
            raise SystemExit(f"machine mismatch for paired run {instance_sha}")

        base_par2 = statistics.median(left["par2"] for left, _right in paired)
        treat_par2 = statistics.median(right["par2"] for _left, right in paired)
        base_wall = statistics.median(left["wall_seconds"] for left, _right in paired)
        treat_wall = statistics.median(
            right["wall_seconds"] for _left, right in paired
        )
        majority = len(paired) // 2 + 1
        base_solved = (
            sum(left["status"] in ("sat", "unsat") for left, _right in paired)
            >= majority
        )
        treat_solved = (
            sum(right["status"] in ("sat", "unsat") for _left, right in paired)
            >= majority
        )
        if treat_solved and not base_solved:
            label = 1
        elif base_solved and not treat_solved:
            label = 0
        elif base_solved and treat_solved:
            material = treat_wall <= base_wall * args.ratio
            material = material and treat_wall <= base_wall - args.min_seconds
            label = 1 if material else 0
        else:
            label = 0

        utility = base_par2 - treat_par2
        timeout = paired[0][0]["timeout_seconds"]
        weight = abs(utility) / timeout if timeout > 0 else 0
        weight = max(0.25, min(2.0, weight))
        feature_names = instance["feature_names"]
        features = instance["features"]
        rows.append(
            {
                "instance_sha256": instance_sha,
                "family_id": instance["family_id"],
                "split": instance["split"],
                "label": label,
                "utility": f"{utility:.17g}",
                "weight": f"{weight:.17g}",
                **{name: features[name] for name in feature_names},
            }
        )

    if not rows:
        raise SystemExit("no complete baseline/treatment pairs")
    feature_names = instances[rows[0]["instance_sha256"]]["feature_names"]
    if feature_names != DATASET.FEATURE_NAMES:
        raise SystemExit(
            "dataset feature ABI does not match router_dataset.py; "
            "recollect before training"
        )
    fieldnames = DATASET.TRAINING_CSV_COLUMNS
    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)
    positives = sum(int(row["label"]) for row in rows)
    print(
        f"wrote {len(rows)} paired rows ({positives} treatment-positive, "
        f"{len(rows) - positives} baseline/tie) for solver "
        f"{selected_solver[:12]} to {args.out}"
    )
    if skipped:
        print(f"skipped {skipped} instances without complete pairs")


if __name__ == "__main__":
    main()
