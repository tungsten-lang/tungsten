"""How predictable is the contact from the state at (swing start + d)? Ridge regression, 5-fold CV, on all noisy dumps."""
import sys, glob
import numpy as np
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/kick")
import kprobe as P
import kseries as S   # joint index table J

CK = "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/kick/ckpt/p1base/"
files = sorted(glob.glob(CK + "p1base_n0.05_dx*.pkl.gz") + glob.glob(CK + "p1base_n0.1_dx*.pkl.gz"))
packs = []
for f in files:
    p = P.load(f)
    r = p["row"]
    if r.get("ct_toe") is None:
        continue
    packs.append(p)
print(len(files), "dumps,", len(packs), "with a touch")
def first(tr, lab):
    return next(i for i, r in enumerate(tr) if r["lab"] == lab)
names = ["hip_flexion_r","hip_adduction_r","hip_rotation_r","knee_angle_r","ankle_angle_r","hip_flexion_l","hip_adduction_l","hip_rotation_l","knee_angle_l","ankle_angle_l","flex_extension","lat_bending","axial_rotation"]
def feats(p, k):
    tr, st = p["trace"], p["state"]
    r, s = tr[k], st[k]
    r1 = tr[max(k - 1, 0)]
    ball = r["ball"]
    f = []
    d = r["bof_r"] - ball; f += list(d)
    f += list((r["bof_r"] - r1["bof_r"]) / 0.01)
    f += list(r["pelvis"] - ball)
    f += [r["yaw"]]
    f += list(r["com"] - ball)
    f += list((r["com"] - r1["com"]) / 0.01)
    f += list(r["ank_l"] - ball)
    for n in names: f.append(s["qpos"][S.J[n]])
    for n in names: f.append(s["qvel"][M_DOF[n]])
    return np.array(f)
import mujoco
M = S.M
M_DOF = {n: M.jnt_dofadr[M.joint(n).id] for n in names}
def ridge_cv(X, y, lam=1e-3, folds=6):
    n = len(y); idx = np.arange(n); rng = np.random.default_rng(0); rng.shuffle(idx)
    pred = np.zeros(n)
    for k in range(folds):
        te = idx[k::folds]; tr = np.setdiff1d(idx, te)
        mu, sd = X[tr].mean(0), X[tr].std(0) + 1e-9
        A = (X[tr] - mu) / sd; B = (X[te] - mu) / sd
        w = np.linalg.solve(A.T @ A + lam * len(tr) * np.eye(A.shape[1]), A.T @ (y[tr] - y[tr].mean()))
        pred[te] = B @ w + y[tr].mean()
    ss = ((y - y.mean()) ** 2).sum()
    return 1 - ((y - pred) ** 2).sum() / ss, np.sqrt(((y - pred) ** 2).mean())
ytar = {"contact y cm": np.array([100 * p["row"]["ct_toe"][1] for p in packs]),
        "contact z cm": np.array([100 * p["row"]["ct_toe"][2] for p in packs]),
        "touch time ms": np.array([1000 * p["row"]["t_touch"] for p in packs]),
        "ball speed": np.array([p["row"]["ball_speed"] for p in packs])}
print("outcome std:", {k: round(float(v.std()), 2) for k, v in ytar.items()})
for d in (0, 5, 8, 11, 14, 17):
    X = np.array([feats(p, first(p["trace"], "swing") + d) for p in packs])
    out = []
    for k, y in ytar.items():
        r2, rm = ridge_cv(X, y, lam=0.05)
        out.append(f"{k}: R2 {r2:+.2f} rmse {rm:.2f}")
    print(f"swing start + {d*10:3d} ms ({X.shape[1]} features) | " + " | ".join(out), flush=True)
