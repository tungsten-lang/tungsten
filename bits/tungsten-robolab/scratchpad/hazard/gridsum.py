"""gridsum.py ROWS.jsonl: the margin map of a design. Per config (tag before '|'): starts standing, and over the standing starts the WORST (smallest) |margin| any wrap segment of the RIGHT (swing)
leg reached at control-step resolution in the window (segv_min), which segment it was, the largest fraction of steps within 1e-2 of a tangent, and the parked knee. A config is CLEAR when
that worst |margin| is above 2e-3 in every start (the task's criterion: |margin| > 2e-3 for the whole hold, jitter included)."""
import collections
import json
import sys

import numpy as np

names = json.load(open("/Users/erik/tungsten/bits/tungsten-robolab/out/hazard/seg_names.json"))
right = [i for i, n in enumerate(names) if n.split("@")[0].endswith("_r_tendon") and not n.startswith(("IL_", "LT", "rect"))]
rows = {}
for l in open(sys.argv[1]):
    try:
        r = json.loads(l)
    except Exception:
        continue
    rows[r["tag"]] = r
g = collections.OrderedDict()
for t, r in rows.items():
    g.setdefault(t.rsplit("|", 1)[0], []).append(r)
print(f"{'config':26s} stand/n  worst|m| (right-leg segment)                 near2max  kn_r    clear")
for k, rs in g.items():
    st = [r for r in rs if (r.get("stand_time") or 0) >= r["seconds"] - 0.11 and r.get("segv_min")]
    if not st:
        print(f"{k:26s} 0/{len(rs)}  (none standing)")
        continue
    worst, wname, n2 = 9.0, "", 0.0
    for r in st:
        mn = np.array([float(x) for x in r["segv_min"].split(",")])
        n2v = np.array([float(x) for x in r["segv_near2"].split(",")])
        for i in right:
            if np.isfinite(mn[i]) and mn[i] < worst:
                worst, wname = mn[i], names[i].split("@")[0]
            n2 = max(n2, n2v[i])
    kn = np.median([r["pr_knee_angle_r_late"] for r in st])
    print(f"{k:26s} {len(st)}/{len(rs)}    {worst:9.2e} {wname:28s} {n2:8.3f}  {kn:.4f}  {'yes' if worst > 2e-3 else 'NO'}")
