"""J of a program over all recorded starts of a stage against the predicted crossing position (rank-ordered)."""
import sys, pickle
sys.path.insert(0, "scratchpad/btl2")
import numpy as np
import oracle_lib as O, oracle_search as S, oracle_multi as M
z = np.load(sys.argv[1]); who = sys.argv[2]; bounce_no = int(sys.argv[3]); tlo = float(sys.argv[4]); params = sys.argv[5]; ctl = sys.argv[6]
cachef = sys.argv[7] if len(sys.argv) > 7 else "scratchpad/btl2/runs/rec_cache.npz.pkl"
cache = pickle.load(open(cachef, "rb"))
idx, kt, x = list(z["idx"]), z["kt"], z["x"]
nprog = int(kt[-1]); n = 160
X = np.clip(x.reshape(len(idx), len(kt)), 0, 1) if len(x) == len(idx) * len(kt) else None
rows = []
for key, rec in cache.items():
    if len(key) < 6 or key[1] != params or key[2] != ctl or abs(key[3] - tlo) > 1e-9: continue
    kc = M.crossing_tick(rec, bounce_no=bounce_no)
    if kc is None: continue
    ks = kc - int(z["lead"])
    if ks not in rec["snaps"]: continue
    rp = O.Replay(rec)
    pc = rp.pred_cross(ks)
    base = rec["acts"][ks:ks + n + 1]
    ov = {}
    for r, mi in enumerate(idx):
        arr = base[:n, mi].copy(); arr[:nprog + 1] = np.interp(np.arange(nprog + 1), kt, X[r]); ov[mi] = arr
    out = rp.run(ov, ticks=n, start=ks)
    J, sm = S.evaluate(out, "full", who)
    rows.append((key[0], pc[0], pc[1], pc[2], J, sm.get("v", np.zeros(3)), sm.get("apex", 0), sm.get("gate", 0), sm.get("body", 0), sm.get("touch")))
rows.sort(key=lambda r: r[4])
print("seed  pred x     y      t   |   J   | release v | apex gate body touch")
for r in rows:
    print(f"{r[0]:4d} {r[1]:+.3f} {r[2]:+.3f} {r[3]:.3f} | {r[4]:5.2f} | {np.round(r[5], 2).tolist()} | {r[6]:.2f} {r[7]} {r[8]} {r[9]}")
A = np.array([[r[1], r[2], r[3]] for r in rows]); Jv = np.array([r[4] for r in rows])
print("n", len(rows), "corr of J with pred x, y, t:", [round(float(np.corrcoef(A[:, i], Jv)[0, 1]), 2) for i in range(3)])
