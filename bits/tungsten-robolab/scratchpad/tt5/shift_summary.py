#!/usr/bin/env python3
"""Summary of the shifted-replay sweep (scratchpad/tt5/shift_replay.py): how the outcome of the champion's own stroke moves when it is shifted in time against the same ball path.
    python3 scratchpad/tt5/shift_summary.py [out/tt5/shift_all.jsonl]       from bits/tungsten-robolab"""
import collections
import json
import sys

import numpy as np

path = sys.argv[1] if len(sys.argv) > 1 else "out/tt5/shift_all.jsonl"
rows = [json.loads(l) for l in open(path)]
rows = [r for r in rows if not r.get("error")]
by = collections.defaultdict(dict)
cls = {}
for r in rows:
    by[r["seed"]][r["shift"]] = r
    cls[r["seed"]] = r["cls0"]
shifts = sorted({r["shift"] for r in rows})
full = [s for s in by if len(by[s]) == len(shifts)]
print(f"{len(full)} serves with all {len(shifts)} shifts ({shifts[0]:+.2f} .. {shifts[-1]:+.2f} s) of {len(by)} started; classes of the plain champion:", dict(collections.Counter(cls[s] for s in full)))
print()
print("A. VALIDITY (shift 0, rigid replay of the recorded stroke) against what the real run did:")
for c in ("solved", "touched", "miss"):
    ss = [s for s in full if cls[s] == c]
    r0 = [by[s][0.0] for s in ss]
    print(f"   {c:8s} n {len(ss):3d}: replay solved {sum(1 for r in r0 if r['solved'] and r['solved'] > 0):3d}, touched {sum(1 for r in r0 if r['hit'] and r['hit'] > 0):3d}")
print()
print("B. SOLVED RATE AT EACH FIXED SHIFT (the same shift for every serve; negative = the pad arrives earlier than it did, positive = later):")
print("   shift ms   " + "  ".join(f"{int(1000 * x):+4d}" for x in shifts))
for c in ("all", "solved", "touched", "miss"):
    ss = [s for s in full if c == "all" or cls[s] == c]
    if not ss:
        continue
    print(f"   {c:8s}   " + "  ".join(f"{100 * np.mean([1 if (by[s][x]['solved'] or 0) > 0 else 0 for s in ss]):4.0f}" for x in shifts) + f"   (n {len(ss)}, % solved)")
ss = full
print("   touched    " + "  ".join(f"{100 * np.mean([1 if (by[s][x]['hit'] or 0) > 0 else 0 for s in ss]):4.0f}" for x in shifts) + "   (all serves, % touched)")
rate = [np.mean([1 if (by[s][x]['solved'] or 0) > 0 else 0 for s in ss]) for x in shifts]
print(f"   best global shift {int(1000 * shifts[int(np.argmax(rate))]):+d} ms: {100 * max(rate):.1f} % solved (shift 0: {100 * rate[shifts.index(0.0)]:.1f} %)")
print()
print("C. PER SERVE: the solved WINDOW in shift (the set of shifts whose return is legal)")
for c in ("solved", "touched", "miss"):
    ss = [s for s in full if cls[s] == c]
    win = {s: [x for x in shifts if (by[s][x]['solved'] or 0) > 0] for s in ss}
    ex = [s for s in ss if win[s]]
    print(f"   {c:8s} n {len(ss):3d}: some shift in +-100 ms is solved on {len(ex):3d}", end="")
    if ex:
        need = np.array([min(abs(x) for x in win[s]) for s in ex])
        width = np.array([10 * len(win[s]) for s in ex])
        print(f"; smallest |shift| needed: median {1000 * np.median(need):.0f} ms, p75 {1000 * np.percentile(need, 75):.0f}, p90 {1000 * np.percentile(need, 90):.0f}; window width (10 ms steps) median {np.median(width):.0f} ms, p25 {np.percentile(width, 25):.0f}, p75 {np.percentile(width, 75):.0f}")
    else:
        print()
    if c != "solved":
        for tol in (0.02, 0.03, 0.05, 0.1):
            k = sum(1 for s in ss if win[s] and min(abs(x) for x in win[s]) <= tol + 1e-9)
            print(f"        within +-{int(1000 * tol):3d} ms of its real timing a legal return exists on {k:3d} of {len(ss)}")
print()
ok_any = [s for s in full if any((by[s][x]['solved'] or 0) > 0 for x in shifts)]
print(f"D. TIMING HEADROOM: with the best shift per serve (+-100 ms) {len(ok_any)} of {len(full)} serves are solved = {100 * len(ok_any) / len(full):.1f} % (real timing: {100 * sum(1 for s in full if cls[s] == 'solved') / len(full):.1f} %; optimistic: the best of 21 shifts per serve)")
best = []
for s in ok_any:
    w = [x for x in shifts if (by[s][x]['solved'] or 0) > 0]
    best.append(np.mean(w))
print(f"   centre of the solved window per serve (ms): median {1000 * np.median(best):+.0f}, sd {1000 * np.std(best):.0f}  (the BIAS is the median, the JITTER is the sd)")
