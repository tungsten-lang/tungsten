"""Per-start replay outcome of a fitted table (or the recorded reflex) against the start's schedule features.
    scratchpad/btl5/py scratchpad/btl5/diag3.py out/btl5/c3.pkl [npz|reflex]"""
import pickle, sys
import numpy as np
sys.path.insert(0, "scratchpad/btl5")
import fit3 as F
import oracle_search as S

D = pickle.load(open(sys.argv[1], "rb"))
mode = sys.argv[2] if len(sys.argv) > 2 else "reflex"

class A: pass
a = A()
a.require, a.require_ok, a.xlo, a.xhi, a.ylo, a.yhi, a.vzmin = 3, 2, -0.40, 0.10, 0.15, 0.55, 0.30
act = F.active_set(D, a)
if mode == "reflex":
    x = None; nom = np.array([-0.112, 0.334, 0.597, -0.595, -0.674]); sc = np.array([0.072, 0.051, 0.214, 0.074, 0.144])
else:
    z = np.load(mode); x = z["x"]; nom = z["nom"]; sc = z["sc"]
for r in act:
    r["u"] = np.clip((r["feat"] - nom) / sc, -2.5, 2.5)
data = {r["seed"]: r for r in act}
cfg = {"idx": {s: F.arm_indices(act[0]["rec"]["names"], s) for s in "lr"}, "n": 200, "nb": 6, "gmax": 1.0,
       "arr": {"pos_dz": 0.03, "vel_dz": 0.15, "target": [0.44, -0.26], "vt": [1.55, -1.55], "pre": True, "w_pos": 6.0, "w_vel": 1.0}}
F.init_worker(data, cfg)
rows = []
for r in act:
    J, sm = F.eval_one((x, r["seed"], np.zeros(5)))
    cat = "no_touch" if not sm.get("touch") else ("no_gate" if sm.get("gate", 0) == 0 else ("body" if sm.get("body", 0) > 0 else ("good" if F.is_good(sm, np.array([0.44, -0.26])) else "other")))
    rows.append((cat, J, r))
import collections
print(collections.Counter(c for c, _, _ in rows))
names = ["x", "y", "wflex", "sabd", "elbow"]
for cat in ["good", "no_touch", "no_gate", "body", "other"]:
    sel = [r for c, _, r in rows if c == cat]
    if not sel:
        continue
    Fm = np.array([r["feat"] for r in sel]); vz = np.array([r["vzc"] for r in sel])
    print(cat, len(sel), "feat mean", " ".join(f"{n} {v:+.3f}" for n, v in zip(names, Fm.mean(0))), f"vzc {vz.mean():.2f}", " | sd", Fm.std(0).round(3))
    ok4 = np.mean([r["pass_ok"][3] for r in sel if len(r["pass_ok"]) > 3])
    print("    baseline pass4 ok", round(float(ok4), 2))
