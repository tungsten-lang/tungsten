import sys
sys.path.insert(0, "playground"); sys.path.insert(0, "playground/tasks"); sys.path.insert(0, "scratchpad/btl2")
import numpy as np
from common import load
import oracle_lib as O, oracle_pair as P
zl = np.load("scratchpad/btl2/runs/gs_left_a_g300.npz")
zr = np.load("scratchpad/btl2/runs/gs_right_b_g100.npz")
params = load("scratchpad/btl2/params/pgLR_b.txt")
idxL, idxR = list(zl["idx"]), list(zr["idx"])
nm, K = len(idxL), len(zl["kt"])
TL = zl["x"].reshape(3, nm, K); TR = zr["x"].reshape(3, nm, K)
cfg = {"idxL": idxL, "idxR": idxR, "kt": zl["kt"], "nprog": int(zl["kt"][-1]), "G": 1000.0, "lead": 0.165,
       "touch_thr": params.get("touch_thr", 0.353), "release_thr": params.get("release_thr", 0.376), "push_min": params.get("push_min", 0.02)}
def feat_R(xy):
    return np.clip((xy - zr["nom"]) / zr["sc"], -2.5, 2.5)
for seed in (901, 903, 919):
    rec = O.record(seed, params, "bin/challengers/btl2-b10", 1.70, 3.8, t_last=2.40)
    ks = next(i for i, l in enumerate(rec["labels"]) if "g_run" in l)
    rp = O.Replay(rec)
    pc = rp.pred_cross(ks)
    uL = np.clip((np.array(pc[:2]) - zl["nom"]) / zl["sc"], -2.5, 2.5)
    out = P.run_pair(rp, ks, cfg, TL, uL, TR, feat_R, n=300, stop=False)
    m = len(out["pos"])
    diff = np.abs(out["pos"] - rec["ball"][ks:ks + m]).max(axis=1)
    bad = int(np.argmax(diff > 1e-6)) if (diff > 1e-6).any() else -1
    print(seed, "ks", ks, "release tick", out["release_tick"], "startR", out["startR"], "max ball diff", float(diff.max()), "first diverging tick", bad)
