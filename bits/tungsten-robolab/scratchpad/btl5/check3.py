"""Consistency of the replay's table (fit3.knot_acts) with the closed loop: record a few starts with the table in the loop, compare the
stroking arm's activations from the trigger tick and the replay-predicted release / arrival with the closed loop's.
    scratchpad/btl5/py scratchpad/btl5/check3.py params.txt fit.npz s0 s1 [stage]"""
import os, pickle, sys
import numpy as np
sys.path.insert(0, "scratchpad/btl5"); sys.path.insert(0, "scratchpad/btl4")
import fit3 as F
import prep as P
import rlib

pfile, npz, s0, s1 = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
stage = int(sys.argv[5]) if len(sys.argv) > 5 else 3
out = "out/btl5/chk_" + os.path.basename(pfile).replace(".txt", "")
os.makedirs(out, exist_ok=True)
z = np.load(npz)
B = z["x"].reshape(6, 16, F.NK); nom, sc = z["nom"], z["sc"]
for sd in range(s0, s1):
    rlib.record_start((sd, pfile, "bin/challengers/btl4-final", out, 3.95, 4.9))
    d = P.one((sd, f"{out}/rec_{sd}.pkl", stage))
    if d is None:
        print(sd, "no trigger"); continue
    rec = pickle.load(open(f"{out}/rec_{sd}.pkl", "rb"))
    ks = d["ks"]
    u = np.clip((d["feat"] - nom) / sc, -2.5, 2.5)
    A, live = F.knot_acts(F.table_knots(B, u, 1.0), d["shift"], 100)
    idx = F.arm_indices(rec["names"], d["hand"])
    cl = np.array([rec["acts"][ks + i][idx] for i in range(100)]).T
    dev = np.abs(A - cl)[:, live[:100]]
    print(sd, "ks", ks, "u", np.round(u, 2).tolist(), "max |table - closed-loop act|", round(float(dev.max()), 4), "mean", round(float(dev.mean()), 5), "passes ok", d["pass_ok"][:5])
