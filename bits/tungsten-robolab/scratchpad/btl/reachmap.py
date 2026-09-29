import sys, numpy as np, itertools, json
sys.path.insert(0, "scratchpad/btl")
import armik as A
from armik import tilt, d, m
import mujoco
ARM = A.ARM
def ik_real(side, target, normal, seed, spine=0.55, rot=0.0):
    d.joint("spine_flex").qpos[0] = spine; d.joint("spine_rot").qpos[0] = rot
    adr = [m.jnt_qposadr[m.joint(side + "_" + j).id] for j in ARM]
    lim = [(-0.6, 1.8), (-0.3, 1.4), (-1.4, 1.4), (0.0, 2.5), (-1.2, 1.2), (-0.5, 0.5)]
    pc = np.array([-0.018, 0.0, -0.12])
    def res(q):
        d.qpos[adr] = q; mujoco.mj_kinematics(m, d)
        h = d.body(side + "_hand"); R = h.xmat.reshape(3, 3)
        return np.concatenate([h.xpos + R @ pc - target, 0.5 * (-R[:, 0] - normal)])
    q = np.array(seed, float); lam = 1e-3; r = res(q)
    for _ in range(120):
        J = np.zeros((6, 6))
        for k in range(6):
            dq = np.zeros(6); dq[k] = 1e-5; J[:, k] = (res(q + dq) - r) / 1e-5
        qn = q + np.linalg.solve(J.T @ J + lam * np.eye(6), -J.T @ r)
        qn = np.array([np.clip(v, lo, hi) for v, (lo, hi) in zip(qn, lim)])
        rn = res(qn)
        if rn @ rn < r @ r: q, r, lam = qn, rn, lam / 3
        else: lam *= 4
    res(q)
    return float(np.linalg.norm(r[:3])), float(np.linalg.norm(r[3:]) / 0.5), float(d.body(side + "_forearm").xpos[2]), q
SEEDS = ([0.55, 0.05, -0.5, 1.4, -0.05, 0.1], [0.2, 0.4, -0.3, 0.6, 0.3, 0.0], [0.8, 0.6, -1.0, 1.0, 0.0, 0.0], [0.0, 0.2, 0.0, 1.0, 0.0, 0.0])
out = {}
for spine, rot in ((0.55, 0.0), (0.7, 0.0)):
    for side in "lr":
        sg = 1 if side == "l" else -1
        for x, y, z, a in itertools.product((-0.1, 0.0, 0.1, 0.2, 0.3, 0.4, 0.5), (0.3, 0.38, 0.46), (0.85, 0.95), (0.35, 0.7)):
            u = np.array([0.0, -sg]); n = tilt(u, a)
            target = np.array([x - 0.12 * n[0], sg * y - 0.12 * n[1], z])
            best = min((ik_real(side, target, n, s, spine, rot) for s in SEEDS), key=lambda r: r[0] + 0.1 * r[1])
            out[(spine, side, x, y, z, a)] = best[:3]
for spine in (0.55, 0.7):
    for side in "lr":
        print(f"spine {spine} side {side}: position error (cm) at z 0.85, tilt 0.35 [0.7]; rows y, cols x -0.1..0.5")
        for y in (0.3, 0.38, 0.46):
            print("  y", y, " ".join(f"{100*out[(spine, side, x, y, 0.85, 0.35)][0]:4.1f}[{100*out[(spine, side, x, y, 0.85, 0.7)][0]:4.1f}]e{out[(spine, side, x, y, 0.85, 0.35)][2]:.2f}" for x in (-0.1, 0.0, 0.1, 0.2, 0.3, 0.4, 0.5)))
