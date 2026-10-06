"""R^2 on the BULK (outliers removed: touch within 12 ms of the median, contact >= 40 ms)."""
import sys, json, glob
import numpy as np
sys.path.insert(0, "scratchpad/btl3")
import m1_analyze as A
d = sys.argv[1]
rows = {0: [], 1: [], 2: []}
for fn in sorted(glob.glob(d + "/live_*.npz")):
    z = np.load(fn)
    pl = json.loads(str(z["pass_log"]))
    for si, (side, k0) in enumerate(A.stage_windows(z)):
        rec = A.extract(z, side, k0)
        if rec is None or "rel_v" not in rec: continue
        a = A.arrival(z, rec["kr"])
        rec["arr"] = a[0] if a else None
        rec["ok"] = bool(pl[si]["ok"]) if si < len(pl) else False
        rows[si].append(rec)
for si in (1, 2):
    R = rows[si]
    tt = np.array([r["touch"]["t"] for r in R]); du = np.array([r["touch"]["dur"] for r in R])
    med = np.median(tt)
    bulk = [r for r in R if abs(r["touch"]["t"] - med) <= 0.012 and r["touch"]["dur"] >= 0.04]
    print(f"\n=== stage {si}: bulk {len(bulk)} of {len(R)} (median touch {med*1000:.0f} ms)")
    RV = np.array([r["rel_v"] for r in bulk])
    print("release v mean", np.round(RV.mean(0), 2), "sd", np.round(RV.std(0), 3), "ok", sum(r["ok"] for r in bulk), "/", len(bulk))
    have = [r for r in bulk if r["arr"] is not None]
    ARR = np.array([r["arr"] for r in have]); print("arrival n", len(have), "mean", np.round(ARR.mean(0), 3), "sd", np.round(ARR.std(0), 3))
    outs = {"vx": (np.array([r["rel_v"][0] for r in bulk]), bulk), "vy": (np.array([r["rel_v"][1] for r in bulk]), bulk), "vz": (np.array([r["rel_v"][2] for r in bulk]), bulk),
            "arr_x": (np.array([r["arr"][0] for r in have]), have), "arr_y": (np.array([r["arr"][1] for r in have]), have)}
    sets = [("t0", [("t0", 0)]), ("t0+arm@0", [("t0", 0), ("arm", 0)]), ("t0+arm@0+live@60", [("t0", 0), ("arm", 0), ("arm", 12), ("palm", 12)]),
            ("t0+arm@0+live@120", [("t0", 0), ("arm", 0), ("arm", 24), ("palm", 24)]), ("t0+arm@0+live@150", [("t0", 0), ("arm", 0), ("arm", 30), ("palm", 30)])]
    print(f"{'set':24s}" + "".join(f"{n:>8s}" for n in outs))
    for name, spec in sets:
        line = f"{name:24s}"
        for on, (y, rr) in outs.items():
            X = np.array([np.concatenate([A.feats(r, k, kind) for kind, k in spec]) for r in rr])
            line += f"{A.loo_r2(X, y):8.2f}"
        print(line)
    TG = lambda rr: np.array([np.concatenate([r["touch"]["palm"], r["touch"]["pv"], [r["touch"]["t"]]]) for r in rr])
    line = f"{'touch geometry':24s}"
    for on, (y, rr) in outs.items():
        line += f"{A.loo_r2(TG(rr), y):8.2f}"
    print(line)
