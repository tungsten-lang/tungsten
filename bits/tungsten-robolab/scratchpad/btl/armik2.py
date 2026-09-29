import sys, numpy as np
sys.path.insert(0, "scratchpad/btl")
import armik as A
from armik import ik, tilt, d
R, L = np.array([0.2, -0.38]), np.array([-0.1, 0.46])
for rot in (0.0, -0.3, -0.5):
    for spine in (0.55, 0.75):
        d.joint("spine_rot").qpos[0] = rot
        for side, sp, ot in (("l", L, R), ("r", R, L)):
            u = (ot - sp) / np.linalg.norm(ot - sp)
            for z, a in ((0.95, 0.35), (0.85, 0.35), (0.85, 0.7)):
                n = tilt(u, a); target = np.array([sp[0] - 0.12 * n[0], sp[1] - 0.12 * n[1], z])
                best = min((ik(side, target, n, s, spine=spine) for s in ([0.55, 0.05, -0.5, 1.4, -0.05, 0.1], [-0.3, 0.3, 0.0, 0.8, 0.0, 0.0], [0.2, 0.4, -0.3, 0.6, 0.3, 0.0], [0.3, 0.8, -0.8, 1.0, 0.0, 0.0])), key=lambda r: r[1])
                print(f"rot {rot} spine {spine} {side} z {z} tilt {a}: err {best[1]:.3f} elbow z {best[2][2]:.2f} q {best[0].round(2)}")
