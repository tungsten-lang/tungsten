import sys, numpy as np, mujoco
sys.path.insert(0, "scratchpad/btl")
from reachmap import ik_real, SEEDS
from armik import tilt, d, m
SEEDS2 = SEEDS + ([0.0, 0.3, 0.8, 0.3, 0.0, 0.0], [0.3, 0.3, 1.0, 0.5, 0.3, 0.0], [-0.2, 0.2, 1.2, 0.4, -0.3, 0.0], [0.2, 0.1, -1.0, 0.3, 0.3, 0.0],
                 [0.3, 0.9, 0.3, 1.2, 0, 0], [0.5, 1.2, 0.0, 1.5, 0, 0], [0.2, 1.3, 0.8, 1.0, 0, 0], [0.8, 1.0, -0.5, 1.5, 0, 0])
H, tw = 0.72, 0.5
for side, S, E in (("r", (0.4, -0.3), (0.0, 0.5)), ("l", (0.0, 0.5), (0.4, -0.3))):
    S, E = np.array(S), np.array(E); u = (E - S) / np.linalg.norm(E - S)
    for a in (0.68, 0.9, 1.1):
        n = tilt(u, a); zc = 0.62 + (0.8 - H)
        target = np.array([S[0] - 0.12 * n[0], S[1] - 0.12 * n[1], zc - 0.12 * n[2]])
        sols = []
        for s in SEEDS2:
            err, nerr, ez, q = ik_real(side, target, n, s, 0.55, tw)
            ik_real(side, target, n, q, 0.55, tw)
            el = d.body(side + "_forearm").xpos.copy(); wr = d.body(side + "_hand").xpos.copy()
            sols.append((round(err, 3), round(nerr, 2), q.round(2), el.round(2), wr.round(2)))
        sols.sort(key=lambda r: r[0] + 0.1 * r[1])
        seen = []
        print(side, "tilt", a)
        for r in sols:
            if any(np.linalg.norm(r[3] - s[3]) < 0.05 for s in seen): continue
            seen.append(r); print("  err", r[0], "nerr", r[1], "q", r[2], "elbow", r[3] - [0, 0, 0.08], "wrist", r[4] - [0, 0, 0.08])
