"""Per-stage counts of an official-reset run set (kltable --official ... --json J): by start distance from the phase-1 stance.
   kstages.py J label"""
import json, sys
import numpy as np
J = json.load(open(sys.argv[1]))
label = sys.argv[2]
rows = J[label]
starts = {r[0]: r for r in json.load(open("/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/kick/out/p2_starts_5000_5099.json"))}
off = [r for r in rows if r["noise"] == 1.0 and r["dx"] is None]
print(label, len(off), "official-reset runs")
bins = [("all", 9.0), ("<= 1.0 m", 1.0), ("<= 0.75 m", 0.75), ("<= 0.5 m", 0.5), ("<= 0.3 m", 0.3)]
def stages(r):
    ev = r.get("events") or {}
    tf = r.get("t_fall")
    cy = r.get("cross_y")
    return {"up 1.5 s": tf is None or tf > 1.5,
            "run-up reached the swing (plant landed)": "swing" in ev,
            "toe/foot touched the ball": r.get("t_touch") is not None,
            "ball >= 8.5 m/s": (r.get("ball_speed") or 0) >= 8.5,
            "and inside the window": (r.get("ball_speed") or 0) >= 8.5 and cy is not None and 0.5 < abs(cy) < 3.2,
            "goal": bool(r.get("goal"))}
for name, lim in bins:
    sel = [r for r in off if np.hypot(starts[r["seed"]][1], starts[r["seed"]][2]) <= lim]
    if not sel: continue
    cnt = {}
    for r in sel:
        for k, v in stages(r).items():
            cnt[k] = cnt.get(k, 0) + int(bool(v))
    print(f"  starts {name:10s} n={len(sel):3d} | " + " | ".join(f"{k}: {v}" for k, v in cnt.items()))
