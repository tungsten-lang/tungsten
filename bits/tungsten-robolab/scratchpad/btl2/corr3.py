"""J of a (gain-scheduled) program over the recorded starts of a stage, against the predicted crossing position.
   corr3.py prog.npz hand bounce_no cache_prefix params ctl t_lo"""
import sys, pickle
sys.path.insert(0, "scratchpad/btl2")
import numpy as np
import oracle_lib as O, oracle_search as S, oracle_multi as M
z = np.load(sys.argv[1]); who = sys.argv[2]; bounce_no = int(sys.argv[3]); cachef = sys.argv[4] + ".pkl"; params = sys.argv[5]; ctl = sys.argv[6]; tlo = float(sys.argv[7])
cache = pickle.load(open(cachef, "rb"))
idx, kt, x = list(z["idx"]), z["kt"], z["x"]
nm, K = len(idx), len(kt)
gs = "gs" in z.files
T = x.reshape(3, nm, K) if gs else x.reshape(1, nm, K)
nprog = int(kt[-1]); n = 160
nom = z["nom"] if gs else None; sc = z["sc"] if gs else None
pc = 0 if who == "l" else 1
rows = []
for key, rec in cache.items():
    if len(key) < 6 or key[1] != params or key[2] != ctl or abs(key[3] - tlo) > 1e-9: continue
    rp = O.Replay(rec)
    ks = M.trigger_tick(rec, rp, bounce_no)
    if ks is None: continue
    pcx = rp.pred_cross(ks)
    u = np.clip((np.array(pcx[:2]) - nom) / sc, -2.5, 2.5) if gs else np.zeros(2)
    X = np.clip(T[0] + (u[0] * T[1] + u[1] * T[2] if gs else 0), 0, 1)
    base = rec["acts"][ks:ks + n + 1]
    ov = {}
    for r, mi in enumerate(idx):
        arr = base[:n, mi].copy(); arr[:nprog + 1] = np.interp(np.arange(nprog + 1), kt, X[r]); ov[mi] = arr
    out = rp.run(ov, ticks=n, start=ks, hand_col=pc)
    J, sm = S.evaluate(out, "full", who)
    rows.append((key[0], pcx[0], pcx[1], pcx[2], J, sm.get("v", np.zeros(3)), sm.get("apex", 0), sm.get("gate", 0), sm.get("body", 0), sm.get("touch"), rec["pass_log"]))
rows.sort(key=lambda r: r[4])
print("seed  pred x     y     |   J   | release v | apex gate body touch | pass1/2 gate,body")
for r in rows:
    pl = r[10]
    print(f"{r[0]:4d} {r[1]:+.3f} {r[2]:+.3f} | {r[4]:5.2f} | {np.round(r[5], 2).tolist()} | {r[6]:.2f} {r[7]} {r[8]} {r[9]} | {[ (int(p['gate']), p['body']) for p in pl[:2]]}")
A = np.array([[r[1], r[2]] for r in rows]); Jv = np.array([r[4] for r in rows])
print("n", len(rows), "corr of J with pred x, y:", [round(float(np.corrcoef(A[:, i], Jv)[0, 1]), 2) for i in range(2)])
