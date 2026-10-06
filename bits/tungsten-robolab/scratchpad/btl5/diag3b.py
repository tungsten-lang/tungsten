"""Replay of the recorded reflex stroke: what the delivered ball looks like for starts whose pass 4 was ok in the closed loop vs not."""
import pickle, sys
import numpy as np
sys.path.insert(0, "scratchpad/btl5")
import fit3 as F
D = pickle.load(open("out/btl5/c3.pkl", "rb"))
class A: pass
a = A(); a.require, a.require_ok, a.xlo, a.xhi, a.ylo, a.yhi, a.vzmin = 3, 2, -0.40, 0.10, 0.15, 0.55, 0.30
act = [r for r in F.active_set(D, a) if len(r["pass_ok"]) > 3]
for r in act:
    r["u"] = np.zeros(5)
data = {r["seed"]: r for r in act}
cfg = {"idx": {s: F.arm_indices(act[0]["rec"]["names"], s) for s in "lr"}, "n": 200, "nb": 6, "gmax": 1.0,
       "arr": {"pos_dz": 0.03, "vel_dz": 0.15, "target": [0.44, -0.26], "vt": [1.55, -1.55], "pre": True, "w_pos": 6.0, "w_vel": 1.0}}
F.init_worker(data, cfg)
rows = []
for r in act:
    J, sm = F.eval_one((None, r["seed"], np.zeros(5)))
    if not (sm.get("touch") and sm.get("bounced")):
        continue
    ok = r["pass_ok"][3]
    clean = sm.get("gate", 0) > 0 and sm.get("body", 0) == 0
    rows.append((ok, clean, sm["apex"], sm["arrive"][0], sm["arrive"][1], float(np.hypot(*sm["va"][:2])), sm["v"][0], sm["v"][1], sm["v"][2], sm["bounce"][0], sm["bounce"][1], sm["va"][0], sm["va"][1]))
R = np.array(rows, float)
print("starts with touch+bounce", len(R), "of", len(act), " clean (gate, no body)", int(R[:, 1].sum()), " closed-loop pass4 ok among clean", int(R[(R[:, 1] == 1) & (R[:, 0] == 1)].shape[0]), "/", int(R[:, 1].sum()))
nm = ["apex", "arr_x", "arr_y", "arr_vh", "rel_vx", "rel_vy", "rel_vz", "bnc_x", "bnc_y", "va_x", "va_y"]
for ok in (1, 0):
    S = R[(R[:, 1] == 1) & (R[:, 0] == ok)]
    print("pass4 ok" if ok else "pass4 FAIL", "(clean strokes) n", len(S), " ".join(f"{n} {S[:, 2 + i].mean():+.2f}±{S[:, 2 + i].std():.2f}" for i, n in enumerate(nm)))
