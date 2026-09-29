"""LS step for the live-tracking forehand ready posture: 7 joints -> ready pose (pitch deg, yaw deg, pad z m)."""
import sys, json
import numpy as np
from scipy.optimize import lsq_linear
np.set_printoptions(precision=3, suppress=True)
names = ["elv", "sh_elv", "sh_rot", "elbow", "pro_sup", "dev", "wflex"]
# per +0.1 rad, ready pose at t = 0.25 (id3, lt regime, r9 forehand params, 60 forehand serves)
J = np.array([[-1.547, -1.115, -0.000], [-0.346, 0.023, 0.018], [2.625, 4.321, -0.003], [-3.853, 1.155, 0.027],
              [1.323, 0.103, 0.001], [-5.568, 3.332, 0.011], [-1.729, 4.287, 0.002]]) / 0.1
base = dict(elv=0.9299840570841318, sh_elv=0.6994500243253876, sh_rot=-0.7631094083671583, elbow=1.2802232816371881,
            pro_sup=0.18606054066504996, dev=-0.12436539609764968, wflex=-0.6581560308511314)
lo = np.array([-0.5, 0.0, -1.5, 0.0, -1.5, -0.17, -0.78]); hi = np.array([1.5, 2.0, 1.5, 2.2, 1.5, 0.43, 0.78])
b0 = np.array([base[n] for n in names])
cur = np.array([-19.515, 15.802, 1.358])
tgt = np.array([float(x) for x in sys.argv[1:4]])
lam = float(sys.argv[4]) if len(sys.argv) > 4 else 0.3
for wz in (10.0, 30.0):
    W = np.diag([1.0, 0.5, wz])
    A = np.vstack([W @ J.T, np.sqrt(lam) * np.eye(7)])
    y = np.concatenate([W @ (tgt - cur), np.zeros(7)])
    r = lsq_linear(A, y, bounds=(lo - b0, hi - b0))
    dq = r.x
    print("z weight", wz, "lam", lam, "step", dq, "predicted pose", cur + J.T @ dq)
    print("  new:", {n: round(float(v), 4) for n, v in zip(names, b0 + dq)})
