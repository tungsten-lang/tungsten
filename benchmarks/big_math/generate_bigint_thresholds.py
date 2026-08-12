#!/usr/bin/env python3
"""Generate runtime/generated/bigint_thresholds.h from forced-kernel sweeps,
with mandatory per-cell boxed validation before any non-default value is
emitted.

Soundness contract (see NOTED_TRADEOFFS.md "Forced-kernel threshold
inference — REJECTED"): forced-kernel curves are discontinuous at fixed
shapes and recursive leaves, so neither a first-win rule nor a fitted
crossover is a valid product-threshold oracle.  This generator therefore:

  1. reads a best-of-9 forced sweep (recorded by tune_bigint_thresholds.sh);
  2. PROPOSES a candidate only on a strong, contiguous signal: the
     challenger family must beat the incumbent by more than --margin
     (default 8%) at --run consecutive sweep points (default 3) spanning
     the proposed cutoff, and the proposal must differ from the checked-in
     default;
  3. VALIDATES every proposal with the boxed affected-cell A/B
     (run_variant_ab.py, 9 x 110 ms acceptance policy): accepted only when
     no affected cell regresses more than 5% and the affected geomean is
     at or below 1.0;
  4. emits every macro with provenance: default kept (no proposal), default
     kept (proposal failed its boxed A/B, artifact retained), or tuned
     (artifact retained).

A header consisting entirely of defaults is a valid, meaningful result: it
pins the measured Apple-Silicon values explicitly and re-attests them.
"""

from __future__ import annotations

import argparse
import datetime
import json
import math
import platform
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
HEADER = ROOT / "runtime" / "generated" / "bigint_thresholds.h"
PROVENANCE = ROOT / "runtime" / "generated" / "bigint_thresholds.provenance.json"

# Matrix sizes the boxed harness measures (bench bignum default widths).
MATRIX_SIZES = [1, 2, 3, 4, 8, 16, 24, 32, 40, 48, 64, 128, 256, 384, 448,
                512, 1024, 2048, 4096, 8192]

# macro -> (default, sweep kind, incumbent column(s), challenger column(s),
#           semantic) — semantic "le_school": n <= T stays with incumbent;
#           "lt_lower": n < T stays with incumbent (T is the first challenger n).
THRESHOLDS = {
    "BN_KARA_THRESHOLD": {
        "default": 24, "sweep": "mul", "semantic": "le_school",
        "incumbent": ["school"], "challenger": ["toom2", "t2sum", "t2diff"],
        "ops": ["mul"],
    },
    "BN_TOOM3_THRESHOLD": {
        "default": 341, "sweep": "mul", "semantic": "lt_lower",
        "incumbent": ["toom2", "t2sum", "t2diff"], "challenger": ["toom3"],
        "ops": ["mul"],
    },
    "BN_TOOM4_THRESHOLD": {
        "default": 452, "sweep": "mul", "semantic": "lt_lower",
        "incumbent": ["toom3"], "challenger": ["toom4"],
        "ops": ["mul"],
    },
    "BN_SQR_KARA_THRESHOLD": {
        "default": 56, "sweep": "sqr", "semantic": "le_school",
        "incumbent": ["school"], "challenger": ["toom2", "t2sum", "t2diff"],
        "ops": ["sqr"],
    },
    "BN_SQR_TOOM4_THRESHOLD": {
        "default": 2560, "sweep": "sqr", "semantic": "lt_lower",
        "incumbent": ["toom3"], "challenger": ["toom4"],
        "ops": ["sqr"],
    },
}

# Macros carried into the header verbatim (their values come from boxed
# campaigns, not the forced sweep; retune only through boxed A/Bs).
CARRIED = {
    "BN_TOOM6_THRESHOLD": ("INT32_MAX", "forced toom6 loses 12-63% to toom4 "
                           "at every 384..4096 size (NOTED_TRADEOFFS 'Toom-6 "
                           "enablement')"),
    "BN_SQR_TOOM3_THRESHOLD": ("392", "empty toom3_sq window is correct as "
                               "configured (NOTED_TRADEOFFS mul@384/448 entry)"),
    "BN_SQR_TOOM3_LIMIT": ("392", "pairs with BN_SQR_TOOM3_THRESHOLD"),
    "BN_SQR_TOOM6_THRESHOLD": ("INT32_MAX", "see BN_TOOM6_THRESHOLD"),
    "BN_NTT_THRESHOLD": ("2048", "gate only: bn_top_choice separately keeps "
                         "Toom below BN_PAR_TOOM_LIMIT (16384) and its "
                         "calibrated model picks SSA in-band"),
    "BN_MUL_EQ_T2DIFF_BAND1_LO": ("400", "difference-form override band "
                                  "(boxed campaigns)"),
    "BN_MUL_EQ_T2DIFF_BAND1_HI": ("432", ""),
    "BN_MUL_EQ_T2DIFF_BAND2_LO": ("448", ""),
    "BN_MUL_EQ_T2DIFF_BAND2_HI": ("520", ""),
    "BN_MUL_EQ_T2DIFF_BAND3_LO": ("536", ""),
    "BN_MUL_EQ_T2DIFF_BAND3_HI": ("544", ""),
}

ROW_RE = re.compile(r"^\s*(\d+)((?:\s+(?:NA|\d+(?:\.\d+)?)){5,9})\s+(\w+)\s*$")


def parse_sweep(text: str):
    """Parse run_toom_sweep.sh output into {kind: {n: {family: ns}}}."""
    sweeps: dict[str, dict[int, dict[str, float]]] = {}
    kind = None
    columns: list[str] = []
    for line in text.splitlines():
        if line.startswith("Forced Toom"):
            kind = "sqr" if "square" in line else "mul"
            sweeps.setdefault(kind, {})
            columns = []
            continue
        if line.startswith("limbs"):
            columns = line.split()[1:-1]  # strip "limbs" and "best"
            continue
        match = ROW_RE.match(line)
        if match and kind and columns:
            n = int(match.group(1))
            values = match.group(2).split()
            row = {}
            for name, value in zip(columns, values):
                if value != "NA":
                    row[name] = float(value)
            sweeps[kind][n] = row
    return sweeps


def best_of(row: dict[str, float], families: list[str]) -> float | None:
    values = [row[f] for f in families if f in row]
    return min(values) if values else None


def propose(spec, sweep, margin: float, run: int):
    """Return (candidate, reason).  Candidate == default means no change."""
    default = spec["default"]
    sizes = sorted(sweep)
    if not sizes:
        return default, "no sweep rows"
    wins = []  # (n, challenger_beats_incumbent_with_margin)
    for n in sizes:
        row = sweep[n]
        inc = best_of(row, spec["incumbent"])
        cha = best_of(row, spec["challenger"])
        if inc is None or cha is None:
            continue
        wins.append((n, cha < inc * (1.0 - margin)))
    if not wins:
        return default, "no comparable rows"
    # Find the earliest start of a `run`-length contiguous challenger win
    # streak that persists to the end of the covered range (no later
    # incumbent comeback), the strong-signal rule.
    first_stable = None
    for i in range(len(wins)):
        if all(w for _, w in wins[i:]) and len(wins) - i >= run:
            first_stable = wins[i][0]
            break
    if first_stable is None:
        return default, "no stable challenger run"
    if spec["semantic"] == "le_school":
        candidate = None
        for n, _ in wins:
            if n < first_stable:
                candidate = n
        candidate = candidate if candidate is not None else first_stable - 1
    else:
        candidate = first_stable
    return candidate, f"stable challenger run from n={first_stable}"


def affected_cells(macro: str, spec, old: int, new: int):
    lo, hi = sorted((old, new))
    sizes = [s for s in MATRIX_SIZES if lo <= s <= hi]
    below = [s for s in MATRIX_SIZES if s < lo]
    above = [s for s in MATRIX_SIZES if s > hi]
    if below:
        sizes.insert(0, below[-1])
    if above:
        sizes.append(above[0])
    return spec["ops"], sorted(set(sizes))


def run_ab(macro: str, spec, candidate: int, out_dir: Path, rounds: int,
           target_ms: float) -> tuple[bool, Path]:
    ops, sizes = affected_cells(macro, spec, spec["default"], candidate)
    artifact = out_dir / f"threshold-{macro.lower()}-{candidate}.json"
    cmd = [
        sys.executable, str(HERE / "run_variant_ab.py"),
        "--label", f"threshold-{macro}-{candidate}",
        "--operations", ",".join(ops),
        "--sizes", ",".join(str(s) for s in sizes),
        # = form: argparse rejects a separate leading-dash value token.
        f"--candidate-extra-flags=-D{macro}={candidate}",
        "--rounds", str(rounds), "--target-ms", str(target_ms),
        "--output", str(artifact),
    ]
    print("VALIDATE:", " ".join(cmd), file=sys.stderr)
    subprocess.run(cmd, check=True)
    doc = json.loads(artifact.read_text())
    ratios = [row["candidate_over_baseline_paired_median"]
              for row in doc["results"]]
    geo = math.exp(sum(math.log(r) for r in ratios) / len(ratios))
    ok = geo <= 1.0 and all(r <= 1.05 for r in ratios)
    return ok, artifact


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sweep-log", type=Path, required=True,
                        help="recorded forced sweep (mul, and optionally a "
                             "sqr section) from tune_bigint_thresholds.sh")
    parser.add_argument("--margin", type=float, default=0.08)
    parser.add_argument("--run", type=int, default=3)
    parser.add_argument("--rounds", type=int, default=9)
    parser.add_argument("--target-ms", type=float, default=110.0)
    parser.add_argument("--skip-validation", action="store_true",
                        help="never emit a non-default value; record what "
                             "WOULD have been proposed (safe on a loaded "
                             "host)")
    parser.add_argument("--output", type=Path, default=HEADER)
    args = parser.parse_args()

    sweeps = parse_sweep(args.sweep_log.read_text())
    out_dir = args.output.parent
    out_dir.mkdir(parents=True, exist_ok=True)

    decisions = {}
    for macro, spec in THRESHOLDS.items():
        sweep = sweeps.get(spec["sweep"], {})
        candidate, reason = propose(spec, sweep, args.margin, args.run)
        entry = {"default": spec["default"], "value": spec["default"],
                 "proposal": candidate, "proposal_reason": reason,
                 "status": "default (no proposal)"}
        if candidate != spec["default"]:
            if args.skip_validation:
                entry["status"] = ("default (proposal recorded, validation "
                                   "skipped by flag)")
            else:
                ok, artifact = run_ab(macro, spec, candidate, out_dir,
                                      args.rounds, args.target_ms)
                entry["artifact"] = str(artifact)
                if ok:
                    entry["value"] = candidate
                    entry["status"] = "tuned (boxed A/B accepted)"
                else:
                    entry["status"] = "default (proposal FAILED boxed A/B)"
        decisions[macro] = entry

    commit = subprocess.run(["git", "-C", str(ROOT), "rev-parse", "--short",
                             "HEAD"], capture_output=True, text=True,
                            check=False).stdout.strip()
    cpu = subprocess.run(["sysctl", "-n", "machdep.cpu.brand_string"],
                         capture_output=True, text=True, check=False)
    meta = {
        "generated_at": datetime.datetime.now(datetime.timezone.utc)
                        .isoformat(),
        "commit": commit,
        "cpu": cpu.stdout.strip() or platform.processor(),
        "sweep_log": str(args.sweep_log),
        "margin": args.margin, "run": args.run,
        "rounds": args.rounds, "target_ms": args.target_ms,
        "decisions": decisions,
    }
    PROVENANCE.write_text(json.dumps(meta, indent=2) + "\n")

    lines = [
        "/* Generated by benchmarks/big_math/generate_bigint_thresholds.py",
        f" * commit {commit} · {meta['cpu']}",
        f" * sweep: {args.sweep_log.name} (best-of-9 forced kernels)",
        " * Every non-default value passed the boxed affected-cell A/B",
        " * (9 x 110 ms, no cell >5% regression, geomean <= 1.0); every",
        " * other macro re-attests its checked-in default.  Details in",
        " * bigint_thresholds.provenance.json. */",
        "",
    ]
    for macro, entry in decisions.items():
        lines.append(f"/* {entry['status']} */")
        lines.append(f"#define {macro} {entry['value']}")
    lines.append("")
    lines.append("/* Carried values (boxed-campaign evidence, not sweep-"
                 "inferable): */")
    for macro, (value, why) in CARRIED.items():
        if why:
            lines.append(f"/* {why} */")
        lines.append(f"#define {macro} {value}")
    lines.append("")
    args.output.write_text("\n".join(lines))
    print(f"wrote {args.output}")
    print(f"wrote {PROVENANCE}")
    for macro, entry in decisions.items():
        print(f"  {macro} = {entry['value']} — {entry['status']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
