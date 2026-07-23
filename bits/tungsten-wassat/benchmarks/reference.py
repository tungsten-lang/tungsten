#!/usr/bin/env python3
"""The reference suite: wassat against every installed rival, exit-coded.

This file DEFINES the performance goal. Instances are pinned and the set
only grows. Two classes:

  parity instances — wassat must be within TOLERANCE of the best rival
                     (exit nonzero otherwise; this is a regression gate);
  frontier instances — known-behind, tracked with gap ratios and a per-run
                       budget so the suite stays fast; improving these is
                       the standing goal, regressing parity is failure.

Every verdict is cross-checked between solvers; disagreement is fatal.
"""

from __future__ import annotations

import os
import shutil
import statistics
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WASSAT = os.environ.get("WASSAT", str(ROOT / "bin" / "wassat"))
CADICAL = os.environ.get("CADICAL", shutil.which("cadical") or "")
CMS5 = os.environ.get("CRYPTOMINISAT5", shutil.which("cryptominisat5") or "")
REPS = int(os.environ.get("REPS", "3"))
TOLERANCE = float(os.environ.get("TOLERANCE", "1.5"))
FRONTIER_BUDGET = float(os.environ.get("FRONTIER_BUDGET", "60"))

BMC = "/tmp/satlib/structclean/bmc"
PARITY = [
    ("uuf100-01", "/tmp/satlib/clean/uuf100-430/uuf100-01.cnf"),
    ("uuf250-01", "/tmp/satlib/clean/uuf250-1065/uuf250-01.cnf"),
    ("php87", "/tmp/wassat-satbench/php87.cnf"),
    ("dubois26", "/tmp/satlib/structclean/dubois/dubois26.cnf"),
    ("bmc-ibm-2", f"{BMC}/bmc-ibm-2.cnf"),
    ("bmc-ibm-6", f"{BMC}/bmc-ibm-6.cnf"),
    ("bmc-ibm-10", f"{BMC}/bmc-ibm-10.cnf"),
    ("bmc-ibm-12", f"{BMC}/bmc-ibm-12.cnf"),
]
FRONTIER = [
    ("lr5_37", "/tmp/lr5_37.cnf"),
    ("lr5_41", "/tmp/lr5_41.cnf"),
]


def solvers():
    out = [("wassat", lambda f: [WASSAT, f, "--fast"])]
    if CADICAL:
        out.append(("cadical", lambda f: [CADICAL, "-q", f]))
    if CMS5:
        out.append(("cms5", lambda f: [CMS5, f]))
    return out


def verdict_of(text: str) -> str:
    for line in text.splitlines():
        if line.startswith("s "):
            return line[2:].strip()
    return "NONE"


def run(cmd, timeout):
    t0 = time.perf_counter()
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, check=False)
    except subprocess.TimeoutExpired:
        return timeout, "TIMEOUT"
    return time.perf_counter() - t0, verdict_of(p.stdout)


def median_time(cmd, timeout):
    times, verdicts = [], set()
    for _ in range(REPS):
        t, v = run(cmd, timeout)
        times.append(t)
        verdicts.add(v)
    if len(verdicts) != 1:
        raise SystemExit(f"nondeterministic verdicts {verdicts} for {cmd}")
    return statistics.median(times), verdicts.pop()


def main() -> None:
    if not Path(WASSAT).is_file():
        raise SystemExit(f"wassat not found at {WASSAT}")
    names = [n for n, _ in solvers()]
    print(f"[reference] REPS={REPS} TOLERANCE={TOLERANCE}x  solvers={names}")
    failures = 0

    print("\n== parity instances (regression gate) ==")
    for name, path in PARITY:
        if not Path(path).is_file():
            print(f"  {name}: MISSING ({path})")
            failures += 1
            continue
        rows = {}
        verdicts = {}
        for sname, mk in solvers():
            t, v = median_time(mk(path), 120)
            rows[sname], verdicts[sname] = t, v
        if len(set(verdicts.values()) - {"TIMEOUT"}) > 1:
            print(f"  {name}: VERDICT MISMATCH {verdicts}")
            failures += 1
            continue
        rivals = {k: v for k, v in rows.items() if k != "wassat"}
        best_rival = min(rivals.values()) if rivals else float("inf")
        # sub-100ms rows are process-startup noise, not solver signal
        ok = rows["wassat"] <= max(best_rival * TOLERANCE, 0.10)
        mark = "ok" if ok else "SLOW"
        if not ok:
            failures += 1
        cells = "  ".join(f"{k}={v:.2f}s" for k, v in rows.items())
        print(f"  {name}: {cells}  [{mark}]")

    print("\n== frontier instances (tracked, budgeted) ==")
    for name, path in FRONTIER:
        if not Path(path).is_file():
            print(f"  {name}: missing encoder output, skipped")
            continue
        rival_t = rival_v = None
        if CADICAL:
            rival_t, rival_v = run([CADICAL, "-q", path], 300)
        wt, wv = run([WASSAT, path, "--fast"], FRONTIER_BUDGET)
        if wv not in ("TIMEOUT",) and rival_v and rival_v != "TIMEOUT" and wv != rival_v:
            print(f"  {name}: VERDICT MISMATCH wassat={wv} cadical={rival_v}")
            failures += 1
            continue
        gap = (wt / rival_t) if rival_t else float("nan")
        solved = "SOLVED" if wv != "TIMEOUT" else f"unsolved@{FRONTIER_BUDGET:.0f}s"
        print(f"  {name}: wassat {solved} ({wt:.1f}s)  cadical={rival_t:.1f}s  gap>={gap:.1f}x")

    if failures:
        raise SystemExit(f"\nFAIL: {failures} parity failure(s)")
    print("\nOK: parity held on every gate instance")


if __name__ == "__main__":
    main()
