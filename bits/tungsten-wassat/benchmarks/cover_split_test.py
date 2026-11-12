#!/usr/bin/env python3
"""Differential test for the covering case-split lane (lib/cover_split.w).

    WASSAT=<binary> [CADICAL=<binary>] [CASES=120] python3 cover_split_test.py

Generates conflict-constrained covering formulas (positive rows of width three
and up, negative binary conflicts), half of them with a planted model, and
forces every one through the lane with WASSAT_COVER_SPLIT_FORCE=1 and the row
DFS switched off (WASSAT_COVERING=0). For each formula:

  * the `c mode` line must name the case split -- a differential that never
    reaches the path it is meant to test proves nothing;
  * the verdict must equal CaDiCaL's;
  * a model is replayed here against every clause, independently of the CLI;
  * the same binary with the lane disabled must give the same verdict.

Truncated case lists (WASSAT_COVER_SPLIT_CASES), single-level lists, repeated
row literals and worker counts are rotated through so the list construction is
exercised at its edges, not only at its default.
"""

from __future__ import annotations

import os
import random
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

WASSAT = os.environ.get("WASSAT", "")
CADICAL = os.environ.get("CADICAL", shutil.which("cadical") or "")
CASES = int(os.environ.get("CASES", "120"))
SEED = int(os.environ.get("SEED", "20261112"))
TIMEOUT = float(os.environ.get("TIMEOUT", "60"))

if not WASSAT or not Path(WASSAT).is_file():
    raise SystemExit("set WASSAT to the binary under test")
if not CADICAL:
    raise SystemExit("CaDiCaL not found; set CADICAL")


def verdict(output: str) -> str:
    for line in output.splitlines():
        if line.startswith("s "):
            return line[2:].strip()
    return ""


def mode(output: str) -> str:
    for line in output.splitlines():
        if line.startswith("c mode:"):
            return line
    return ""


def model(output: str) -> set[int]:
    values: set[int] = set()
    for line in output.splitlines():
        if line.startswith("v "):
            values.update(int(t) for t in line[2:].split() if t != "0")
    return values


def satisfies(clauses: list[list[int]], assignment: set[int]) -> bool:
    return all(any(lit in assignment for lit in clause) for clause in clauses)


def generate(rng: random.Random, case: int) -> tuple[int, list[list[int]]]:
    nvars = rng.randint(24, 70)
    nrows = rng.randint(nvars, 4 * nvars)
    planted = case % 2 == 0
    chosen = set(rng.sample(range(1, nvars + 1), rng.randint(4, max(5, nvars // 3))))
    rows: list[list[int]] = []
    for _ in range(nrows):
        width = rng.randint(3, 9)
        row = rng.sample(range(1, nvars + 1), width)
        if planted and not chosen.intersection(row):
            row[rng.randrange(width)] = rng.choice(sorted(chosen))
            row = list(dict.fromkeys(row))
            while len(row) < 3:
                extra = rng.randint(1, nvars)
                if extra not in row:
                    row.append(extra)
        if case % 7 == 3:
            row.append(row[0])            # a repeated literal inside a row
        rows.append(row)
    density = rng.choice([0.05, 0.1, 0.2, 0.35])
    edges: set[tuple[int, int]] = set()
    for a in range(1, nvars + 1):
        for b in range(a + 1, nvars + 1):
            if rng.random() < density and not (planted and a in chosen and b in chosen):
                edges.add((a, b))
    if not edges:
        a, b = sorted(rng.sample([v for v in range(1, nvars + 1) if not (planted and v in chosen)] or [1, 2], 2))
        edges.add((a, b))
    clauses = rows + [[-a, -b] for a, b in sorted(edges)]
    rng.shuffle(clauses)
    return nvars, clauses


def run(cmd: list[str], env: dict[str, str]) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, timeout=TIMEOUT, check=False, env=env)


base_env = {k: v for k, v in os.environ.items() if not k.startswith("WASSAT_")}
base_env["WASSAT_BACKDOOR_TABLES"] = "0"
rng = random.Random(SEED)
sat = unsat = truncated = 0
with tempfile.TemporaryDirectory(prefix="wassat-cover-split-") as directory:
    root = Path(directory)
    for case in range(CASES):
        nvars, clauses = generate(rng, case)
        cnf = root / f"case-{case:04d}.cnf"
        cnf.write_text(
            f"p cnf {nvars} {len(clauses)}\n"
            + "".join(" ".join(map(str, c)) + " 0\n" for c in clauses)
        )
        forced = dict(base_env, WASSAT_COVERING="0", WASSAT_COVER_SPLIT_FORCE="1")
        knob = case % 5
        if knob == 1:
            forced["WASSAT_COVER_SPLIT_CASES"] = "2"      # truncated first row
            truncated += 1
        elif knob == 2:
            forced["WASSAT_COVER_SPLIT_CASES"] = "5"
            truncated += 1
        elif knob == 3:
            forced["WASSAT_COVER_SPLIT_WORKERS"] = "2"
        elif knob == 4:
            forced["WASSAT_COVER_SPLIT_SLS"] = "0"
        ours = run([WASSAT, str(cnf), "--fast"], forced)
        if "covering case split" not in mode(ours.stdout):
            raise SystemExit(f"lane not reached on {cnf}: {mode(ours.stdout)!r}\n{ours.stderr[-400:]}")
        reference = run([CADICAL, str(cnf)], base_env)
        ours_v, ref_v = verdict(ours.stdout), verdict(reference.stdout)
        if ours_v != ref_v or ours_v not in ("SATISFIABLE", "UNSATISFIABLE"):
            keep = Path(tempfile.gettempdir()) / f"cover-split-mismatch-{case}.cnf"
            shutil.copy(cnf, keep)
            raise SystemExit(f"verdict mismatch on case {case} ({keep}): Wassat={ours_v!r}, CaDiCaL={ref_v!r}")
        if ours_v == "SATISFIABLE":
            if not satisfies(clauses, model(ours.stdout)):
                raise SystemExit(f"invalid case-split model on case {case}")
            sat += 1
        else:
            unsat += 1
        plain = run([WASSAT, str(cnf), "--fast"], dict(base_env, WASSAT_COVER_SPLIT="0"))
        if "covering case split" in mode(plain.stdout):
            raise SystemExit(f"WASSAT_COVER_SPLIT=0 did not disable the lane on case {case}")
        if verdict(plain.stdout) != ours_v:
            raise SystemExit(f"lane on/off disagree on case {case}: {ours_v} vs {verdict(plain.stdout)}")

    # Shapes the lane must leave alone even when forced.
    for name, clauses in (
        ("mixed-binary", [[1, 2, 3], [4, 5, 6], [-1, -4], [2, -5]]),
        ("negative-long", [[1, 2, 3], [-4, -5, -6], [-1, -4]]),
        ("unit", [[1, 2, 3], [4, 5, 6], [-1, -4], [5]]),
        ("no-conflicts", [[1, 2, 3], [4, 5, 6]]),
    ):
        cnf = root / f"{name}.cnf"
        cnf.write_text("p cnf 6 %d\n" % len(clauses) + "".join(" ".join(map(str, c)) + " 0\n" for c in clauses))
        out = run([WASSAT, str(cnf), "--fast"], dict(base_env, WASSAT_COVERING="0", WASSAT_COVER_SPLIT_FORCE="1"))
        if "covering case split" in mode(out.stdout):
            raise SystemExit(f"lane admitted the non-covering shape {name}")
        ref = run([CADICAL, str(cnf)], base_env)
        if verdict(out.stdout) != verdict(ref.stdout):
            raise SystemExit(f"verdict mismatch on rejected shape {name}")

print(
    f"OK: {CASES} forced case-split formulas, {sat} SAT models replayed, "
    f"{unsat} UNSAT verdicts matching CaDiCaL, {truncated} with truncated case lists"
)
