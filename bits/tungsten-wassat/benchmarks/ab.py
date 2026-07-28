#!/usr/bin/env python3
"""Interleaved N-way A/B of wassat binaries over reference.py's own rows.

    BINS="base=/path/w-a,cand=/path/w-b" python3 benchmarks/ab.py

One corpus walk, N columns. Binaries alternate WITHIN each row within each
rep, so drift and contention hit every column equally -- this is a relative
measurement and does not need a quiet machine the way an absolute one does.

A column may be the SAME binary under a different environment:

    BINS="off=/p/w:WASSAT_SLS_PLATEAU=0,on=/p/w:WASSAT_SLS_PLATEAU=100000"

which is the preferred form when the knob has an env override -- those columns
cannot differ by compiler drift, only by the knob.

MEDIAN, not min. wassat's race is nondeterministic and some rows are sharply
bimodal -- em_7_3_6_fbc ranges 5.3s to 36.0s across five runs of the SAME
binary in the SAME configuration. min-of-N estimates the lucky tail, so it
reports whichever column happened to draw the fast mode and can INVERT a
comparison outright (it scored a change 0.89 that the reference suite, which
takes medians, scored as a regression). reference.py uses medians; so does
this.

Every run's `s` line is checked against reference.py's published expectation
and against the other columns; a disagreement is fatal regardless of speed.
Rows where every column exceeds the budget are reported separately and
EXCLUDED from the geomean rather than silently scored as ties.

Env: AB_REPS (3), AB_BUDGET (25s), AB_OUT (ab.json).
"""
from __future__ import annotations

import json
import math
import os
import re
import statistics
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import reference as R  # noqa: E402

BINS: list[tuple[str, str, dict]] = []
for spec in os.environ["BINS"].split(","):
    label, rest = spec.split("=", 1)
    env_over: dict[str, str] = {}
    if ":" in rest:
        rest, envs = rest.split(":", 1)
        for kv in envs.split(";"):
            k, v = kv.split("=", 1)
            env_over[k] = v
    BINS.append((label, rest, env_over))

REPS = int(os.environ.get("AB_REPS", "3"))
BUDGET = float(os.environ.get("AB_BUDGET", "25"))
OUT = Path(os.environ.get("AB_OUT", "ab.json"))
S_RE = re.compile(r"^s (.+)$", re.M)
EXPECT = {"sat": "SATISFIABLE", "unsat": "UNSATISFIABLE"}

rows: list[tuple[str, str, str | None]] = []
for name, path in R.PARITY:
    if Path(path).exists():
        rows.append((name, path, None))
for _fam, name, rel, expect in R.SURVEY:
    p = R.EXT / rel
    if p.exists():
        rows.append((name, str(p), expect))

print(f"{len(rows)} rows x {len(BINS)} columns x {REPS} reps, budget {BUDGET}s")
for label, b, ev in BINS:
    v = subprocess.run([b, "--version"], capture_output=True, text=True)
    print(f"  {label:<10} {b}  {v.stdout.strip()!r} rc={v.returncode}  env={ev or '-'}")
    if v.returncode != 0 or "Wassat" not in v.stdout:
        sys.exit("FATAL: --version smoke test failed")
print(flush=True)


def run(binary: str, path: str, env_over: dict) -> tuple[float, str, int]:
    env = dict(os.environ, **env_over)
    t0 = time.perf_counter()
    try:
        p = subprocess.run([binary, path, "--fast"], capture_output=True,
                           text=True, timeout=BUDGET, env=env)
    except subprocess.TimeoutExpired:
        return BUDGET, "TIMEOUT", -1
    m = S_RE.search(p.stdout)
    return time.perf_counter() - t0, (m.group(1).strip() if m else "<none>"), p.returncode


times: dict[tuple[str, str], list[float]] = {}
verdicts: dict[tuple[str, str], set[str]] = {}
fatal: list[str] = []
dead: set[str] = set()

for rep in range(REPS):
    for name, path, expect in rows:
        if name in dead:
            continue
        for label, binary, ev in BINS:
            wall, s, rc = run(binary, path, ev)
            times.setdefault((name, label), []).append(wall)
            verdicts.setdefault((name, label), set()).add(s)
            want = EXPECT.get(expect or "", None)
            if s == "TIMEOUT":
                pass
            elif rc not in (10, 20):
                fatal.append(f"{name} [{label}] rep{rep}: exit {rc}, s={s!r}")
            elif want and s != want:
                fatal.append(f"{name} [{label}] rep{rep}: got {s!r} expected {want!r}")
        cells = "  ".join(
            f"{lb}=" + ("T/O" if "TIMEOUT" in verdicts[(name, lb)] else f"{times[(name, lb)][-1]:.3f}")
            for lb, _, _ in BINS)
        print(f"  rep{rep} {name[:34]:<35} {cells}", flush=True)
        if rep == 0 and all("TIMEOUT" in verdicts[(name, lb)] for lb, _, _ in BINS):
            dead.add(name)
            print("       ^ every column over budget; dropped from later reps", flush=True)
    print(f"-- rep {rep} done", flush=True)
    OUT.write_text(json.dumps({f"{k[0]}|{k[1]}": v for k, v in times.items()}, indent=1))

for name, _p, _e in rows:
    seen = {lb: verdicts.get((name, lb), set()) - {"TIMEOUT"} for lb, _, _ in BINS}
    nonempty = [v for v in seen.values() if v]
    if nonempty and any(v != nonempty[0] for v in nonempty):
        fatal.append(f"{name}: columns disagree: {seen}")

base = BINS[0][0]
print()
for lb, _, _ in BINS[1:]:
    rs = []
    for name, _p, _e in rows:
        if name in dead or (name, lb) not in times:
            continue
        a = statistics.median(times[(name, base)])
        b = statistics.median(times[(name, lb)])
        if max(a, b) >= BUDGET - 0.5:
            continue
        rs.append((b / a, name, a, b))
    if not rs:
        continue
    g = math.exp(sum(math.log(r) for r, _, _, _ in rs) / len(rs))
    faster = sum(1 for r, _, _, _ in rs if r < 0.95)
    slower = sum(1 for r, _, _, _ in rs if r > 1.05)
    print(f"{lb} vs {base}: geomean {g:.4f} of MEDIANS over {len(rs)} rows "
          f"({faster} faster >5%, {slower} slower >5%, {len(rs)-faster-slower} within 5%)")
    print(f"    total {sum(x[2] for x in rs):.1f}s -> {sum(x[3] for x in rs):.1f}s")
    print("    best :", ", ".join(f"{n[:20]} {r:.2f}x" for r, n, _, _ in sorted(rs)[:5]))
    print("    worst:", ", ".join(f"{n[:20]} {r:.2f}x" for r, n, _, _ in sorted(rs, reverse=True)[:5]))
if dead:
    print("\nover budget for every column (excluded): " + ", ".join(sorted(dead)))
if fatal:
    print("\nFATAL:")
    for f in fatal:
        print("  " + f)
    sys.exit(1)
print("\nall verdicts agree and match the published expectations")
