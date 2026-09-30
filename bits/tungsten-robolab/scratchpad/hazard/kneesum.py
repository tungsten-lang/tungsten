"""kneesum.py ROWS.jsonl [--thr 0.02]: per config (tag before '|'), over its starts: falls, parked knee, and the wrap segments that come close to their tangent in the watched window.

A segment is listed when, in any start, it spends more than --thr of the control steps (default 2 %) within 1e-2 of its tangent (segv_near2), with the worst start's
fraction within 1e-2 / 1e-3, its smallest |margin| and tangent crossings (flips); 'none' = every one of the 68 segments stays clear (the goal).
"""
import collections
import json
import sys

import numpy as np

args = sys.argv[1:]
thr = 0.02
if "--thr" in args:
    i = args.index("--thr")
    thr = float(args[i + 1])
    del args[i:i + 2]
names = json.load(open("/Users/erik/tungsten/bits/tungsten-robolab/out/hazard/seg_names.json"))
rows = {}
for l in open(args[0]):
    try:
        r = json.loads(l)
    except Exception:
        continue
    rows[r["tag"]] = r
g = collections.OrderedDict()
for t, r in rows.items():
    g.setdefault(t.rsplit("|", 1)[0], []).append(r)
vec = lambda r, k: np.array([float(x) for x in r[k].split(",")]) if r.get(k) else None
print(f"{'config':18s} n fall kn_r    legF | segments with > {thr:.0%} of the window within 1e-2 (worst start: near2 / near3, min|m|, crossings)")
for k, rs in g.items():
    ok = [r for r in rs if r.get("segv_near2")]
    fall = sum(1 for r in rs if r.get("fallen") or (r.get("stand_time") or 0) < r["seconds"] - 0.11)
    if not ok:
        print(f"{k:18s} {len(rs)} {fall} (no segment stats)")
        continue
    kn = np.median([r["pr_knee_angle_r_late"] for r in ok])
    lf = np.median([r.get("pr_legf_late", np.nan) for r in ok])
    bad = []
    for j, nm in enumerate(names):
        n2 = np.array([vec(r, "segv_near2")[j] for r in ok])
        if n2.max() > thr:
            w = int(np.argmax(n2))
            r = ok[w]
            bad.append((n2.max(), f"{nm.split('@')[0]} {n2.max():.2f}/{vec(r, 'segv_near3')[j]:.3f} min {vec(r, 'segv_min')[j]:.1e} x{int(vec(r, 'segv_flips')[j])}"))
    bad.sort(reverse=True)
    print(f"{k:18s} {len(rs)} {fall} {kn:.4f} {lf:6.1f} | " + ("; ".join(b for _, b in bad[:5]) if bad else "none"))
