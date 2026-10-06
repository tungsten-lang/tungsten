"""Release / delivery statistics of clean strokes of a stage-3 table (npz) in the replay.   scratchpad/btl5/py scratchpad/btl5/rel3.py data.pkl table.npz [target args fixed to V1]"""
import pickle, sys
import numpy as np
sys.path.insert(0, "scratchpad/btl5")
import fit3 as F
D = pickle.load(open(sys.argv[1], "rb"))
class A: pass
a = A(); a.require, a.require_ok, a.xlo, a.xhi, a.ylo, a.yhi, a.vzmin = 3, 2, -0.40, 0.10, 0.15, 0.55, 0.30
act = F.active_set(D, a)
cfg = {"idx": {s: F.arm_indices(act[0]["rec"]["names"], s) for s in "lr"}, "n": 200, "nb": 6, "gmax": 4.0,
       "arr": {"pos_dz": 0.04, "vel_dz": 0.2, "target": [0.44, -0.26], "vt": [1.5, -1.5], "pre": True, "w_pos": 4.0, "w_vel": 1.0, "apex_min": 0.68, "w_apex": 5.0}}
z = np.load(sys.argv[2]); x = z["x"]; nom = z["nom"]; sc = z["sc"]
for r in act:
    r["u"] = np.clip((r["feat"] - nom) / sc, -2.5, 2.5)
F.init_worker({r["seed"]: r for r in act}, cfg)
import collections
cat = collections.Counter(); rows = []
for r in act:
    J, sm = F.eval_one((x, r["seed"], np.zeros(5)))
    if not sm.get("touch"): cat["no_touch"] += 1; continue
    if not sm.get("bounced"): cat["no_bounce"] += 1; continue
    if sm.get("gate", 0) == 0: cat["no_gate"] += 1; continue
    if sm.get("body", 0) > 0: cat["body"] += 1; continue
    cat["clean"] += 1
    rows.append(list(sm["v"]) + list(sm["bounce"]) + [sm["apex"]] + list(sm["arrive"]) + list(sm["va"]))
R = np.array(rows)
print(dict(cat), "clean release v (%.2f, %.2f, %.2f) sd (%.2f, %.2f, %.2f) apex %.2f±%.2f arrival (%.2f±%.2f, %.2f±%.2f) va (%.2f, %.2f)" % (*R[:, :3].mean(0), *R[:, :3].std(0), R[:, 5].mean(), R[:, 5].std(), R[:, 6].mean(), R[:, 6].std(), R[:, 7].mean(), R[:, 7].std(), *R[:, 8:10].mean(0)))
