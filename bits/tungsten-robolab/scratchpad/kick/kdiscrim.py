"""Which swing-start features separate good from bad kicks (AUC), over the noisy dumps."""
import sys, glob
import numpy as np
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/kick")
import kprobe as P
import kseries as S
CK = "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/kick/ckpt/p1base/"
files = sorted(glob.glob(CK + "p1base_n0.05_dx*.pkl.gz") + glob.glob(CK + "p1base_n0.1_dx*.pkl.gz"))
M = S.M
names = ["hip_flexion_r","hip_adduction_r","hip_rotation_r","knee_angle_r","ankle_angle_r","subtalar_angle_r","hip_flexion_l","hip_adduction_l","hip_rotation_l","knee_angle_l","ankle_angle_l","flex_extension","lat_bending","axial_rotation"]
qa = {n: M.jnt_qposadr[M.joint(n).id] for n in names}
da = {n: M.jnt_dofadr[M.joint(n).id] for n in names}
def first(tr, lab): return next(i for i, r in enumerate(tr) if r["lab"] == lab)
X, y, fn = [], [], None
import math
for f in files:
    p = P.load(f); r = p["row"]
    sp = r["ball_speed"] or 0; cy = r["cross_y"]
    good = (sp > 8.5 and cy is not None and 0.5 < abs(cy) < 3.2)
    tr, st = p["trace"], p["state"]
    k = first(tr, "swing"); a, s = tr[k], st[k]
    a1 = tr[k - 1]
    feats = {}
    d = a["bof_r"] - a["ball"]
    feats.update({"toe dx": d[0], "toe dy": d[1], "toe dz": d[2]})
    v = (a["bof_r"] - a1["bof_r"]) / 0.01
    feats.update({"toe vx": v[0], "toe vy": v[1], "toe vz": v[2]})
    feats.update({"pelvis dx": a["pelvis"][0] - a["ball"][0], "pelvis dy": a["pelvis"][1], "pelvis z": a["pelvis"][2], "yaw": a["yaw"]})
    feats.update({"com dx": a["com"][0] - a["ball"][0], "com dy": a["com"][1], "com z": a["com"][2]})
    vc = (a["com"] - a1["com"]) / 0.01
    feats.update({"com vx": vc[0], "com vy": vc[1], "com vz": vc[2]})
    feats.update({"Lank dx": a["ank_l"][0] - a["ball"][0], "Lank dy": a["ank_l"][1], "Lfoot yaw": math.atan2(*(a["toe_l"] - a["ank_l"])[1::-1])})
    feats.update({"hip r - pelvis dy": a["hip_r"][1] - a["pelvis"][1]})
    for n in names:
        feats["q " + n] = s["qpos"][qa[n]]
        feats["qd " + n] = s["qvel"][da[n]]
    feats["t of swing"] = a["t"]
    fn = list(feats); X.append([feats[k2] for k2 in fn]); y.append(good)
X = np.array(X); y = np.array(y)
print(len(y), "dumps;", int(y.sum()), "good")
def auc(x, y):
    pos, neg = x[y], x[~y]
    if len(pos) == 0 or len(neg) == 0: return 0.5
    # Mann-Whitney
    r = np.argsort(np.argsort(np.concatenate([pos, neg]))) + 1
    return (r[:len(pos)].sum() - len(pos) * (len(pos) + 1) / 2) / (len(pos) * len(neg))
res = sorted([(abs(auc(X[:, i], y) - 0.5), fn[i], auc(X[:, i], y), X[y, i].mean(), X[~y, i].mean(), X[:, i].std()) for i in range(len(fn))], reverse=True)
for r in res[:22]:
    print(f"{r[1]:20s} AUC {r[2]:.2f}  mean good {r[3]:+.3f} bad {r[4]:+.3f} (std {r[5]:.3f})")
