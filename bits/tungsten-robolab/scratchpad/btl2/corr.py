"""How the outcome of a program depends on the ball's arrival: J and release velocity against the predicted crossing position."""
import sys, pickle
sys.path.insert(0, "scratchpad/btl2")
import numpy as np
import oracle_lib as O, oracle_search as S, oracle_multi as M
z = np.load(sys.argv[1]); who = sys.argv[2]
cache = pickle.load(open("scratchpad/btl2/runs/rec_cache.npz.pkl", "rb"))
idx, kt, x = list(z["idx"]), z["kt"], z["x"]
nprog = int(kt[-1]); n = 160
X = np.clip(x.reshape(len(idx), len(kt)), 0, 1)
bounce_no = 2 if who == "l" else 3
rows = []
for key, rec in cache.items():
    if (who == "l") == ("pgL" in key[1]): continue
    kc = M.crossing_tick(rec, bounce_no=bounce_no)
    if kc is None: continue
    ks = kc - int(z["lead"])
    if ks not in rec["snaps"]: continue
    rp = O.Replay(rec)
    base = rec["acts"][ks:ks + n + 1]
    ov = {}
    for r, mi in enumerate(idx):
        arr = base[:n, mi].copy(); arr[:nprog + 1] = np.interp(np.arange(nprog + 1), kt, X[r]); ov[mi] = arr
    out = rp.run(ov, ticks=n, start=ks)
    J, sm = S.evaluate(out, "full", who)
    p = rec["ball"][kc]
    rows.append((key[0], p[0], p[1], rec["ballv"][kc][0], rec["ballv"][kc][1], J, sm.get("v", np.zeros(3)), sm.get("apex", 0)))
rows.sort(key=lambda r: r[5])
print("seed  cross x   y    vx    vy |  J  | release v | apex")
for r in rows:
    print(f"{r[0]:4d} {r[1]:+.3f} {r[2]:+.3f} {r[3]:+.2f} {r[4]:+.2f} | {r[5]:5.2f} | {np.round(r[6], 2).tolist()} | {r[7]:.2f}")
A = np.array([[r[1], r[2], r[3], r[4]] for r in rows]); Jv = np.array([r[5] for r in rows])
print("corr of J with crossing x, y, vx, vy:", [round(float(np.corrcoef(A[:, i], Jv)[0, 1]), 2) for i in range(4)])
