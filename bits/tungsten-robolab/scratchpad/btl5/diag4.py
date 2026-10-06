"""Stage 4 replay: delivered-ball statistics of the table (fit4 npz) over the active set: arrival, apex, speed, categories."""
import pickle, sys
import numpy as np
sys.path.insert(0, "scratchpad/btl5")
import fit3 as F
D = pickle.load(open(sys.argv[1], "rb"))
z = np.load(sys.argv[2]); x = z["x"]; nom = z["nom"]; sc = z["sc"]
class A: pass
a = A(); a.require, a.require_ok, a.xlo, a.xhi, a.ylo, a.yhi, a.vzmin = 4, 3, 0.1, 0.7, -0.55, 0.0, -0.1
act = F.active_set(D, a)
for r in act:
    r["u"] = np.clip((r["feat"] - nom) / sc, -2.5, 2.5)
data = {r["seed"]: r for r in act}
cfg = {"idx": {s: F.arm_indices(act[0]["rec"]["names"], s) for s in "lr"}, "n": 200, "nb": 6, "gmax": 4.0,
       "arr": {"pos_dz": 0.04, "vel_dz": 0.2, "target": [-0.09, 0.30], "vt": [-1.58, 1.58], "pre": True, "w_pos": 4.0, "w_vel": 1.0, "apex_min": 0.68, "w_apex": 5.0}}
F.init_worker(data, cfg)
rows = []
for r in act:
    J, sm = F.eval_one((x, r["seed"], np.zeros(5)))
    if not (sm.get("touch") and sm.get("bounced")):
        rows.append(("no_touch" if not sm.get("touch") else "no_bounce", J)); continue
    clean = sm.get("gate", 0) > 0 and sm.get("body", 0) == 0
    rows.append(("clean" if clean else ("no_gate" if sm.get("gate", 0) == 0 else "body"), J, sm["apex"], sm["arrive"][0], sm["arrive"][1], float(np.hypot(*sm["va"][:2])), sm["va"][0], sm["va"][1]))
import collections
print(collections.Counter(r[0] for r in rows))
C = np.array([r[2:] for r in rows if r[0] == "clean"], float)
print("clean strokes n", len(C), "apex %.2f±%.2f arrival (%.2f±%.2f, %.2f±%.2f) vh %.2f±%.2f va (%.2f, %.2f)" % (C[:, 0].mean(), C[:, 0].std(), C[:, 1].mean(), C[:, 1].std(), C[:, 2].mean(), C[:, 2].std(), C[:, 3].mean(), C[:, 3].std(), C[:, 4].mean(), C[:, 5].mean()))
print("J by category:", {k: round(float(np.mean([r[1] for r in rows if r[0] == k])), 2) for k in set(r[0] for r in rows)})
