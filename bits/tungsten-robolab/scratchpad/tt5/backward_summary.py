#!/usr/bin/env python3
"""Selection rules over the backward-planning oracle runs (scratchpad/tt5/backward_plan.py). None of R1-R3 looks at the ball's outcome; R4 does (hindsight, reference only).
  R1 max-cushion: the candidate with the best model landing margin (no reachability test)
  R2 backward plan: among the candidates the ideal-arm servo REACHED (pad error at the planned contact <= 1.5 cm and <= 2.5 deg) the best margin; none reached: the smallest error
  R3 min-error: the candidate the servo reached best (ignores the margin)
  R4 hindsight: a solved candidate exists
Reference: the single fixed plan of the earlier ladder (plan bn0.1) with the same servo: 47 of 70 on the validation serves, 63 of 100 on set B.
    python3 scratchpad/tt5/backward_summary.py [out/tt5/bwd.jsonl]       from bits/tungsten-robolab"""
import collections
import json
import sys

import numpy as np

rows = [json.loads(l) for l in open(sys.argv[1] if len(sys.argv) > 1 else "out/tt5/bwd.jsonl")]
rows = [r for r in rows if not r.get("error") and r.get("perr")]
by = collections.defaultdict(list)
for r in rows:
    pe = r["perr"]
    r["pos"] = 100 * float(np.linalg.norm(pe[:3]))
    r["ang"] = float(pe[3])
    r["reached"] = r["pos"] <= 1.5 and r["ang"] <= 2.5
    r["err"] = r["pos"] / 1.5 + r["ang"] / 2.5
    r["ok"] = (r["solved"] or 0) > 0
    by[r["seed"]].append(r)
sets = {"validation 98030-98099": range(98030, 98100), "set B 830000-830099": range(830000, 830100)}
ref = {"validation 98030-98099": (47, 70), "set B 830000-830099": (63, 100)}
rules = {
    "R1 max cushion (no reachability test)": lambda c: max(c, key=lambda r: r["margin"]),
    "R2 BACKWARD PLAN (reached, then best margin)": lambda c: (max([r for r in c if r["reached"]], key=lambda r: r["margin"]) if any(r["reached"] for r in c) else min(c, key=lambda r: r["err"])),
    "R3 min error (ignores the margin)": lambda c: min(c, key=lambda r: r["err"]),
}
for sname, rng in sets.items():
    ss = [s for s in rng if s in by]
    if not ss:
        continue
    print(f"\n{sname}: {len(ss)} serves with candidates ({np.mean([len(by[s]) for s in ss]):.0f} per serve; {sum(1 for s in ss if any(r['reached'] for r in by[s]))} have at least one REACHED candidate; {sum(1 for s in ss if any(r['ok'] for r in by[s]))} have a solved one (hindsight))")
    print(f"   reference, one fixed plan (bn0.1): {ref[sname][0]} of {ref[sname][1]} = {100 * ref[sname][0] / ref[sname][1]:.0f} %")
    for name, f in rules.items():
        ch = [f(by[s]) for s in ss]
        k = sum(1 for r in ch if r["ok"])
        print(f"   {name:48s}: solved {k:3d} of {len(ss)} = {100 * k / len(ss):4.0f} %   (touched {sum(1 for r in ch if (r['hit'] or 0) > 0)}; chosen offset median {1000 * np.median([r['off'] for r in ch]):+.0f} ms, sd {1000 * np.std([r['off'] for r in ch]):.0f}; margin median {np.median([r['margin'] for r in ch]):.2f})")
    hk = sum(1 for s in ss if any(r["ok"] for r in by[s]))
    print(f"   {'R4 hindsight (a solved candidate exists)':48s}: solved {hk:3d} of {len(ss)} = {100 * hk / len(ss):4.0f} %")
    # among reached candidates only: how often is a reached candidate solved, by margin band
    reached = [r for s in ss for r in by[s] if r["reached"]]
    print(f"   reached candidates: {len(reached)}; solved {100 * np.mean([r['ok'] for r in reached]):.0f} % of them; by margin: " +
          ", ".join(f"[{lo:.1f},{hi:.1f}) {100 * np.mean([r['ok'] for r in reached if lo <= r['margin'] < hi]):.0f} % (n {sum(1 for r in reached if lo <= r['margin'] < hi)})" for lo, hi in ((0.05, 0.2), (0.2, 0.4), (0.4, 0.6), (0.6, 2.0)) if any(lo <= r['margin'] < hi for r in reached)))
