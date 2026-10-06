"""With the stage-3 table in the loop: replay summaries of the closed-loop stage-3 stroke vs the closed-loop pass 4 / 5 results."""
import pickle, sys
import numpy as np
sys.path.insert(0, "scratchpad/btl5")
import fit3 as F
D = pickle.load(open(sys.argv[1], "rb"))
class A: pass
a = A(); a.require, a.require_ok, a.xlo, a.xhi, a.ylo, a.yhi, a.vzmin = 3, 2, -0.40, 0.10, 0.15, 0.55, 0.30
act = [r for r in F.active_set(D, a) if len(r["pass_ok"]) > 3]
for r in act:
    r["u"] = np.zeros(5)
data = {r["seed"]: r for r in act}
cfg = {"idx": {s: F.arm_indices(act[0]["rec"]["names"], s) for s in "lr"}, "n": 200, "nb": 6, "gmax": 1.0,
       "arr": {"pos_dz": 0.06, "vel_dz": 0.25, "target": [0.41, -0.25], "vt": [0.72, -0.92], "pre": True, "w_pos": 3.0, "w_vel": 1.0, "apex_min": 0.5, "w_apex": 5.0}}
F.init_worker(data, cfg)
rows = []
for r in act:
    J, sm = F.eval_one((None, r["seed"], np.zeros(5)))
    if not (sm.get("touch") and sm.get("bounced")):
        rows.append((r["pass_ok"][2], r["pass_ok"][3], False, np.nan, np.nan, np.nan, np.nan, np.nan, np.nan)); continue
    clean = sm.get("gate", 0) > 0 and sm.get("body", 0) == 0
    rows.append((r["pass_ok"][2], r["pass_ok"][3], clean, sm["apex"], sm["arrive"][0], sm["arrive"][1], sm["va"][0], sm["va"][1], float(np.hypot(*sm["va"][:2]))))
R = np.array(rows, float)
print("active", len(R), " clean strokes", int(np.nansum(R[:, 2])), " pass3 ok", int(R[:, 0].sum()), " pass4 ok", int(R[:, 1].sum()))
cl = R[:, 2] == 1
print("pass 4 ok among clean:", int(R[cl, 1].sum()), "/", int(cl.sum()), " among not clean:", int(R[~cl, 1].sum()), "/", int((~cl).sum()))
nm = ["apex", "arr_x", "arr_y", "va_x", "va_y", "vh"]
for lab, sel in (("clean, pass4 ok", cl & (R[:, 1] == 1)), ("clean, pass4 fail", cl & (R[:, 1] == 0))):
    S = R[sel]
    print(f"{lab:20s} n {len(S):3d} " + " ".join(f"{n} {np.nanmean(S[:, 3 + i]):+.2f}±{np.nanstd(S[:, 3 + i]):.2f}" for i, n in enumerate(nm)))
import collections
c = collections.Counter()
for r in act:
    p = r["pass_log"][3]
    c[(p["outcome"], p["gate"], p["body"] > 0, r["pass_ok"][3])] += 1
print(c.most_common())
