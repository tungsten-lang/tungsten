"""R^2 of the TOUCH geometry (palm - ball offset, palm velocity at the first touch, touch time) from the live features at +k ms,
and the sd of each: what a feedback stroke would be correcting."""
import sys, json, glob
import numpy as np
sys.path.insert(0, "scratchpad/btl3")
import m1_analyze as A
d = sys.argv[1]
rows = {0: [], 1: [], 2: []}
for fn in sorted(glob.glob(d + "/live_*.npz")):
    z = np.load(fn)
    for si, (side, k0) in enumerate(A.stage_windows(z)):
        rec = A.extract(z, side, k0)
        if rec is None or "rel_v" not in rec: continue
        rows[si].append(rec)
names = ["off_x", "off_y", "off_z", "pv_x", "pv_y", "pv_z", "t_touch"]
for si in (0, 1, 2):
    R = rows[si]
    Y = np.array([np.concatenate([r["touch"]["palm"], r["touch"]["pv"], [r["touch"]["t"]]]) for r in R])
    print(f"\n=== stage {si}: n {len(R)}; sd of the touch geometry: " + " ".join(f"{n} {s:.3f}" for n, s in zip(names, Y.std(0))))
    print(f"{'set':34s}" + "".join(f"{n:>8s}" for n in names))
    sets = [("t0", [("t0", 0)]), ("t0+arm@0", [("t0", 0), ("arm", 0)])]
    for k in (6, 12, 18, 24, 30):
        sets.append((f"t0+arm@0+arm,palm@+{k*5}ms", [("t0", 0), ("arm", 0), ("arm", k), ("palm", k)]))
    for name, spec in sets:
        line = f"{name:34s}"
        for j in range(Y.shape[1]):
            X = np.array([np.concatenate([A.feats(r, k, kind) for kind, k in spec]) for r in R])
            line += f"{A.loo_r2(X, Y[:, j]):8.2f}"
        print(line)
