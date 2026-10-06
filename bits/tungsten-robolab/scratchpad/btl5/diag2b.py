"""Stage 2 (the right return): the replay of the recorded stroke, what the delivered ball looks like for starts whose pass 3 / pass 4 were ok in the closed loop."""
import pickle, sys
import numpy as np
sys.path.insert(0, "scratchpad/btl5")
import fit3 as F
D = pickle.load(open("out/btl5/c2.pkl", "rb"))
class A: pass
a = A(); a.require, a.require_ok, a.xlo, a.xhi, a.ylo, a.yhi, a.vzmin = 2, 1, 0.2, 0.6, -0.5, -0.05, 0.3
act = F.active_set(D, a)
for r in act:
    r["u"] = np.zeros(5)
data = {r["seed"]: r for r in act}
cfg = {"idx": {s: F.arm_indices(act[0]["rec"]["names"], s) for s in "lr"}, "n": 200, "nb": 6, "gmax": 1.0,
       "arr": {"pos_dz": 0.03, "vel_dz": 0.15, "target": [-0.11, 0.34], "vt": [-1.5, 1.5], "pre": True, "w_pos": 6.0, "w_vel": 1.0}}
F.init_worker(data, cfg)
rows = []
for r in act:
    J, sm = F.eval_one((None, r["seed"], np.zeros(5)))
    if not (sm.get("touch") and sm.get("bounced")):
        continue
    ok3 = r["pass_ok"][2] if len(r["pass_ok"]) > 2 else False
    ok4 = r["pass_ok"][3] if len(r["pass_ok"]) > 3 else False
    clean = sm.get("gate", 0) > 0 and sm.get("body", 0) == 0
    rows.append((ok3, ok4, clean, sm["apex"], sm["arrive"][0], sm["arrive"][1], float(np.hypot(*sm["va"][:2])), sm["va"][0], sm["va"][1], sm["v"][0], sm["v"][1], sm["v"][2]))
R = np.array(rows, float)
print("starts", len(R), "clean", int(R[:, 2].sum()), "ok3 among clean", int(R[(R[:, 2] == 1) & (R[:, 0] == 1)].shape[0]), "ok4 among clean", int(R[(R[:, 2] == 1) & (R[:, 1] == 1)].shape[0]))
nm = ["apex", "arr_x", "arr_y", "arr_vh", "va_x", "va_y", "rel_vx", "rel_vy", "rel_vz"]
for lab, sel in (("pass4 ok", (R[:, 2] == 1) & (R[:, 1] == 1)), ("pass3 ok, pass4 fail", (R[:, 2] == 1) & (R[:, 0] == 1) & (R[:, 1] == 0)), ("pass3 fail", (R[:, 2] == 1) & (R[:, 0] == 0))):
    S = R[sel]
    print(f"{lab:22s} n {len(S):3d} " + " ".join(f"{n} {S[:, 3 + i].mean():+.2f}±{S[:, 3 + i].std():.2f}" for i, n in enumerate(nm)))
