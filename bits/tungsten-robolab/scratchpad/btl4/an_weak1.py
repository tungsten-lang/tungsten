"""What makes a weak left return: release vz vs the touch geometry / palm velocity / touch time (live traces of the baseline)."""
import glob, json, sys
import numpy as np
sys.path.insert(0, "scratchpad/btl3")
import m1_analyze as A
rows = []
for fn in sorted(glob.glob("out/btl4/live_base/live_*.npz")):
    z = np.load(fn)
    ws = A.stage_windows(z)
    if len(ws) < 2:
        continue
    side, k0 = ws[1]
    rec = A.extract(z, side, k0)
    if rec is None or "rel_v" not in rec:
        continue
    t = rec["touch"]
    rows.append(dict(vz=rec["rel_v"][2], vx=rec["rel_v"][0], vy=rec["rel_v"][1], tt=t["t"], dur=t["dur"], off=t["palm"], pv=t["pv"], pc=rec["pc"]))
n = len(rows)
vz = np.array([r["vz"] for r in rows]); tt = np.array([r["tt"] for r in rows]) * 1000
pv = np.array([r["pv"] for r in rows]); off = np.array([r["off"] for r in rows]); dur = np.array([r["dur"] for r in rows]) * 1000
print("n", n, "release vz mean %.2f sd %.2f; touch time ms mean %.0f sd %.0f; contact ms %.0f sd %.0f" % (vz.mean(), vz.std(), tt.mean(), tt.std(), dur.mean(), dur.std()))
lo = vz > np.quantile(vz, 0.75)   # release vz is negative downward: weakest = closest to zero = highest
print("weakest quartile (vz > %.2f) vs the rest:" % np.quantile(vz, 0.75))
for nm, v in (("touch time ms", tt), ("contact ms", dur), ("palm speed |pv|", np.linalg.norm(pv, axis=1)), ("palm vz", pv[:, 2]), ("palm vx", pv[:, 0]), ("palm vy", pv[:, 1]),
              ("offset x", off[:, 0]), ("offset y", off[:, 1]), ("offset z", off[:, 2])):
    print(f"  {nm:16s} weak {v[lo].mean():7.3f} (sd {v[lo].std():.3f})   rest {v[~lo].mean():7.3f} (sd {v[~lo].std():.3f})   corr with vz {np.corrcoef(v, vz)[0,1]:+.2f}")
X = np.column_stack([tt, np.linalg.norm(pv, axis=1), pv[:, 2], off])
Z = (X - X.mean(0)) / X.std(0)
A_ = np.column_stack([np.ones(n), Z])
beta = np.linalg.lstsq(A_, vz, rcond=None)[0]
print("R^2 of release vz on (touch time, palm speed, palm vz, offset xyz):", round(1 - ((vz - A_ @ beta) ** 2).sum() / ((vz - vz.mean()) ** 2).sum(), 2))
