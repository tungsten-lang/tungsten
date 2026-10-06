"""Stage 4 with a table in the loop (recorded): the delivered ball of clean strokes for starts whose pass 5 was ok vs not."""
import pickle, sys
import numpy as np
sys.path.insert(0, "scratchpad/btl5")
import fit3 as F
D = pickle.load(open(sys.argv[1], "rb"))
class A: pass
a = A(); a.require, a.require_ok, a.xlo, a.xhi, a.ylo, a.yhi, a.vzmin = 4, 3, 0.1, 0.7, -0.55, 0.0, -0.1
act = [r for r in F.active_set(D, a) if len(r["pass_ok"]) > 4]
for r in act:
    r["u"] = np.zeros(5)
data = {r["seed"]: r for r in act}
cfg = {"idx": {s: F.arm_indices(act[0]["rec"]["names"], s) for s in "lr"}, "n": 200, "nb": 6, "gmax": 1.0,
       "arr": {"pos_dz": 0.04, "vel_dz": 0.2, "target": [-0.09, 0.30], "vt": [-1.58, 1.58], "pre": True, "w_pos": 4.0, "w_vel": 1.0, "apex_min": 0.68, "w_apex": 5.0}}
F.init_worker(data, cfg)
rows = []
for r in act:
    J, sm = F.eval_one((None, r["seed"], np.zeros(5)))
    if not (sm.get("touch") and sm.get("bounced")):
        rows.append((r["pass_ok"][4], False) + (np.nan,) * 7); continue
    clean = sm.get("gate", 0) > 0 and sm.get("body", 0) == 0
    rows.append((r["pass_ok"][4], clean, sm["apex"], sm["arrive"][0], sm["arrive"][1], sm["va"][0], sm["va"][1], float(np.hypot(*sm["va"][:2])), J))
R = np.array(rows, float)
cl = R[:, 1] == 1
print("active", len(R), "clean", int(cl.sum()), "pass5 ok", int(R[:, 0].sum()), "ok among clean", int(R[cl, 0].sum()))
nm = ["apex", "arr_x", "arr_y", "va_x", "va_y", "vh", "J"]
for lab, sel in (("clean, pass5 ok", cl & (R[:, 0] == 1)), ("clean, pass5 fail", cl & (R[:, 0] == 0)), ("not clean", ~cl)):
    S = R[sel]
    print(f"{lab:18s} n {len(S):3d} " + " ".join(f"{n} {np.nanmean(S[:, 2 + i]):+.2f}±{np.nanstd(S[:, 2 + i]):.2f}" for i, n in enumerate(nm)))
