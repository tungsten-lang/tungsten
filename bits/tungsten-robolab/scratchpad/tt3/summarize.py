"""Table of the oracle runs (agent T3): per tag, per set and pooled: solved / hit of 100, failure classes, paired flips against O0 (same serves), and the three sigmas at contact
(scratchpad/tt2/noise.py functions; for the kinematic-paddle runs the injected noise is the plan's, so the sigmas are not measured against the controller's aim).
    .venv-myo/bin/python scratchpad/tt3/summarize.py TAG [TAG ...]   (tags: o0, o1, o2, o3, o4a, ...)"""
import json, os, sys
import numpy as np
HERE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(HERE, "playground")); sys.path.insert(0, os.path.join(HERE, "scratchpad", "tt2"))
import noise as nz
from tasks.myo_tt import failure_class

SHORT = {"solved": "solved", "hit: out (long, wide or back)": "out", "hit: landed on own half": "own", "hit: net": "net", "miss: pad below the ball": "below",
         "miss: pad above the ball": "above", "miss: lateral (out of reach)": "lateral", "miss: within 10 cm (rim/timing)": "rim<10cm"}

def load(tag, s):
    f = f"out/tt3/{tag}_{s}.jsonl"
    if not os.path.exists(f): return None
    return {r["seed"]: r for r in map(json.loads, open(f)) if "error" not in r}

def line(tag, with_sigma=True):
    o0 = {s: load("o0", s) for s in "AB"}
    res = {}; cls = {}; cls_set = {"A": {}, "B": {}}; flips = [0, 0]
    tot = {"solved": 0, "hit": 0, "n": 0}
    parts = []
    for s in "AB":
        rows = load(tag, s)
        if rows is None: continue
        sol = sum(1 for r in rows.values() if r.get("solved", 0) > 0); hit = sum(1 for r in rows.values() if r.get("hit", 0) > 0)
        tot["solved"] += sol; tot["hit"] += hit; tot["n"] += len(rows)
        parts.append(f"{s}: {sol}/{len(rows)} hit {hit}")
        for r in rows.values():
            c = SHORT.get(failure_class(r), failure_class(r)); cls[c] = cls.get(c, 0) + 1; cls_set[s][c] = cls_set[s].get(c, 0) + 1
            a = o0[s].get(r["seed"]); 
            if a is not None:
                b0, b1 = a.get("solved", 0) > 0, r.get("solved", 0) > 0
                flips[0] += int(b0 and not b1); flips[1] += int(b1 and not b0)
    if not tot["n"]: return f"{tag}: no data"
    z = (flips[1] - flips[0]) / np.sqrt(max(flips[0] + flips[1], 1))
    p = tot["solved"] / tot["n"]
    se = np.sqrt(p * (1 - p) / tot["n"])
    txt = f"{tag:<10} | " + " | ".join(parts) + f" | pooled {tot['solved']}/{tot['n']} = {100 * p:.1f}% (+-{100 * se:.1f}) hit {tot['hit']}/{tot['n']} | vs O0 flips lost {flips[0]} gained {flips[1]} z {z:+.1f}\n    classes pooled " + json.dumps(cls) + "\n    classes A " + json.dumps(cls_set["A"]) + "\n    classes B " + json.dumps(cls_set["B"])
    if with_sigma and os.path.isdir(f"out/tt3/logs_{tag}") and tag.startswith(("o1", "o2", "o3", "rec", "o0")):
        rows = []
        for s in "AB":
            rr = load(tag, s)
            if rr: rows += list(rr.values())
        py, pv, pl = nz.pitch_yaw(rows), nz.pad_velocity(rows), nz.place_error(rows, f"out/tt3/logs_{tag}")
        txt += f"\n    sigmas (pooled hits): pitch {py.get('pitch_sigma', float('nan')):.1f} deg, pad velocity {pv.get('sigma', float('nan')):.3f} m/s, place {pl.get('sigma_cm', float('nan')):.2f} cm (median dist {pl.get('median_cm', float('nan')):.1f} cm)"
    return txt

if __name__ == "__main__":
    for t in sys.argv[1:]:
        print(line(t))
