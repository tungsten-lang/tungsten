"""Replay prediction vs closed loop for a stage-3 table: for seeds s0..s1 record the closed loop with params (table in the loop), then compare
J_pred (replay of the OLD baseline record with the table override) with J_cl (replay of the NEW record, no override = the closed loop itself).
    scratchpad/btl5/py scratchpad/btl5/check3b.py params.txt fit.npz old_data.pkl s0 s1 lead [obj args as env]"""
import os, pickle, sys
import numpy as np
sys.path.insert(0, "scratchpad/btl5"); sys.path.insert(0, "scratchpad/btl4")
import fit3 as F
import prep as P
import rlib
import oracle_search as S

pfile, npz, old, s0, s1, lead = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), int(sys.argv[5]), float(sys.argv[6])
out = "out/btl5/chk_" + os.path.basename(pfile).replace(".txt", "")
os.makedirs(out, exist_ok=True)
z = np.load(npz)
B = z["x"].reshape(6, 16, F.NK); nom, sc = z["nom"], z["sc"]
Dold = {r["seed"]: r for r in pickle.load(open(old, "rb"))}
S.ARR.update({"pos_dz": 0.06, "vel_dz": 0.25, "target": [0.41, -0.25], "vt": [0.72, -0.92], "pre": True, "w_pos": 3.0, "w_vel": 1.0, "apex_min": 0.50, "w_apex": 5.0})
rows = []
cfg = {"idx": None, "n": 200, "nb": 6, "gmax": 4.0, "arr": dict(S.ARR)}
from multiprocessing import freeze_support
for sd in range(s0, s1):
    rlib.record_start((sd, pfile, "bin/challengers/btl4-final", out, 3.95, 4.9))
    dn = P.one((sd, f"{out}/rec_{sd}.pkl", 3, lead))
    if dn is None or sd not in Dold:
        print(sd, "no trigger"); continue
    do = Dold[sd]
    cfg["idx"] = {s: F.arm_indices(do["rec"]["names"], s) for s in "lr"}
    for d in (do, dn):
        d["u"] = np.clip((d["feat"] - nom) / sc, -2.5, 2.5)
    # which tick did the closed loop's trigger fire at? (the arm's activations equal the table's from the trigger on)
    rec = pickle.load(open(f"{out}/rec_{sd}.pkl", "rb"))
    idx = F.arm_indices(rec["names"], "l")
    devs = {}
    for off in range(-8, 9):
        ks_ = dn["ks"] + off
        pc_ = P.pred_cross5(P._RP["rp"], ks_) if False else None
        devs[off] = None
    best = None
    A_, live_ = F.knot_acts(F.table_knots(B, dn["u"] if "u" in dn else np.clip((dn["feat"] - nom) / sc, -2.5, 2.5), 4.0), dn["shift"], 60)
    cl = np.array([rec["acts"][dn["ks"] + i][idx] for i in range(60)]).T
    dev0 = float(np.abs(A_ - cl)[:, live_[:60]].max())
    F.init_worker({sd: do, -sd: dn}, cfg)
    x = z["x"]
    Jp, smp = F.eval_one((x, sd, np.zeros(5)))
    Jc, smc = F.eval_one((None, -sd, np.zeros(5)))
    def desc(sm):
        if not sm.get("touch"): return "no_touch"
        if "arrive" not in sm: return "no_bounce"
        return f"gate{sm.get('gate')} body{sm.get('body')} apex{sm.get('apex', 0):.2f} arr({sm['arrive'][0]:+.2f},{sm['arrive'][1]:+.2f}) rel({sm['v'][0]:+.2f},{sm['v'][1]:+.2f},{sm['v'][2]:+.2f})"
    print(sd, f"Jpred {Jp:5.2f} [{desc(smp)}]  Jcl {Jc:5.2f} [{desc(smc)}]  dev {dev0:.3f} passes {dn['pass_ok'][:5]}  feat-diff {np.abs(do['feat']-dn['feat']).max():.4f} shift-diff {abs(do['shift']-dn['shift']):.5f}")
