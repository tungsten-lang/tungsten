#!/usr/bin/env python3
"""The RETENTION-AWARE backward plan (3 Oct 2026). From the welded still-pad sweep with the final joint configuration of every candidate (out/tt5/bwd_wq.jsonl): for each candidate the
joint-space MIN-JERK move from the champion's own arm posture at t_start (X log, tick t_start) to that configuration over T = t_hit - lead - blend - t_start needs at most
A = max_j 5.77 |dq_j| / T^2 rad/s^2. In the hand-held runs the paddle stayed in the hand in 95 % of the plans with A below 92 rad/s^2 (and 90 % of them were solved), 43 % at 92-223, 10 % at 234-390.
Selection R5: among the candidates the servo REACHED (pad error <= 1.5 cm and <= 2.5 deg in the welded sweep) with A <= A_max the best landing margin; none: the reached candidate of smallest A.
Writes out/tt5/rerun_r5_<A_max>.json in the format of rerun_qdry0.json (seed, off, kind, qlast) for joint_rerun.py --src r5_<A_max>.
    .venv-myo/bin/python scratchpad/tt5/accel_select.py --t-start 0.12 --blend 0.10 --lead 0.05 --amax 60,90,130       from bits/tungsten-robolab"""
import argparse
import collections
import json

import numpy as np

ap = argparse.ArgumentParser()
ap.add_argument("--src", default="out/tt5/bwd_wq.jsonl")
ap.add_argument("--t-start", type=float, default=0.12)
ap.add_argument("--blend", type=float, default=0.10)
ap.add_argument("--lead", type=float, default=0.05)
ap.add_argument("--amax", default="60,90,130")
ap.add_argument("--tag", default="", help="output name suffix: rerun_r5<tag>_<A_max>.json")
a = ap.parse_args()
rows = [json.loads(l) for l in open(a.src)]
by = collections.defaultdict(list)
cache = {}
for r in rows:
    if r.get("error") or not r.get("perr") or not r.get("qlast"):
        continue
    sd = r["seed"]
    if sd not in cache:
        cache[sd] = np.load(f"out/tt3/logs_o0/{sd}.npz", allow_pickle=True)["X"]
    q0 = cache[sd][max(int(round(a.t_start / 0.01)) - 1, 0), :7]
    T = max(r["t_hit_plan"] - a.lead - a.blend - a.t_start, 0.05)
    dq = np.array(r["qlast"]) - q0
    r["A"] = float(np.max(5.77 * np.abs(dq) / T ** 2))
    pe = r["perr"]
    r["pos"], r["ang"] = 100 * float(np.linalg.norm(pe[:3])), float(pe[3])
    r["reached"] = r["pos"] <= 1.5 and r["ang"] <= 2.5
    by[sd].append(r)
for amax in [float(x) for x in a.amax.split(",")]:
    out, n_ok, n_fb = [], 0, 0
    for sd, c in sorted(by.items()):
        ok = [r for r in c if r["reached"] and r["A"] <= amax]
        if ok:
            ch = max(ok, key=lambda r: r["margin"])
            n_ok += 1
        else:
            reach = [r for r in c if r["reached"]]
            ch = min(reach or c, key=lambda r: r["A"])
            n_fb += 1
        out.append(dict(seed=sd, off=ch["off"], kind=ch["kind"], qlast=ch["qlast"], A=ch["A"], margin=ch["margin"], solved_weld=ch["solved"]))
    json.dump(out, open(f"out/tt5/rerun_r5{a.tag}_{int(amax)}.json", "w"))
    print(f"A_max {amax:5.0f}: {n_ok} serves have a reached candidate with A <= A_max (chosen A median {np.median([o['A'] for o in out if o['A'] <= amax]) if n_ok else float('nan'):.0f}, margin median {np.median([o['margin'] for o in out]):.2f}); fallback (smallest A) for {n_fb}; weld solved of the chosen: {sum(1 for o in out if (o['solved_weld'] or 0) > 0)} of {len(out)}")
