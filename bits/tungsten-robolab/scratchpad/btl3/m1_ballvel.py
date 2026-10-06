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
        a = A.arrival(z, rec["kr"])
        rec["arr"] = a[0] if a else None
        rec["bv0"] = z["ballv"][k0 - 1].copy(); rec["bp0"] = z["ball"][k0 - 1].copy()
        rows[si].append(rec)
for si in (1, 2):
    R = rows[si]
    tt = np.array([r["touch"]["t"] for r in R]); med = np.median(tt)
    for label, sel in (("all", R), ("bulk", [r for r in R if abs(r["touch"]["t"] - med) <= 0.012 and r["touch"]["dur"] >= 0.04])):
        have = [r for r in sel if r["arr"] is not None]
        outs = {"vx": (np.array([r["rel_v"][0] for r in sel]), sel), "vy": (np.array([r["rel_v"][1] for r in sel]), sel), "vz": (np.array([r["rel_v"][2] for r in sel]), sel),
                "arr_x": (np.array([r["arr"][0] for r in have]), have), "arr_y": (np.array([r["arr"][1] for r in have]), have)}
        print(f"\nstage {si} {label} n {len(sel)}")
        print(f"{'set':30s}" + "".join(f"{n:>8s}" for n in outs))
        for name, extra, usearm in (("t0", False, False), ("t0 + ball v", True, False), ("t0 + arm@0", False, True), ("t0 + ball v + arm@0", True, True)):
            line = f"{name:30s}"
            for on, (y, rr) in outs.items():
                X = []
                for r in rr:
                    f = [A.feats(r, 0, "t0")]
                    if extra: f.append(r["bv0"])
                    if usearm: f.append(A.feats(r, 0, "arm"))
                    X.append(np.concatenate(f))
                line += f"{A.loo_r2(np.array(X), y):8.2f}"
            print(line)
