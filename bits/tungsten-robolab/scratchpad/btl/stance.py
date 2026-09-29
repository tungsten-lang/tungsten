"""Leg IK for pivot stances (pelvis fixed at 0.80): foot at (x, y) on the floor, flat, toe pointing along yaw."""
import os, sys, numpy as np, mujoco
sys.path.insert(0, "playground"); sys.path.insert(0, "playground/tasks")
from dribble_v3 import DribbleV3Task
t = DribbleV3Task()
m = mujoco.MjModel.from_xml_string(t.xml(t.builder())); d = mujoco.MjData(m)
t.reset(m, d)
NAMES = ["hip_flex", "hip_abd", "hip_rot", "knee", "ankle"]
ANKLE_Z = 0.079

def fk(side, q):
    for n, v in zip(NAMES, q): d.joint(f"{side}_{n}").qpos[0] = v
    mujoco.mj_kinematics(m, d)
    a = d.body(f"{side}_foot").xpos.copy(); R = d.body(f"{side}_foot").xmat.reshape(3, 3).copy()
    return a, R

def ik(side, x, y, yaw=0.0, seed=None, wflat=0.3):
    q = np.array(seed if seed is not None else [0.57, 0.1, 0.0, 1.14, -0.57])
    rng = [m.jnt_range[m.joint(f"{side}_{n}").id] for n in NAMES]
    def res(q):
        a, R = fk(side, q)
        fwd = R[:, 0]
        return np.array([a[0] - x, a[1] - y, a[2] - ANKLE_Z, wflat * R[0, 2], wflat * R[1, 2], 0.2 * (fwd[1] - np.sin(yaw))])
    clip = lambda q: np.array([np.clip(v, lo + 0.01, hi - 0.01) for v, (lo, hi) in zip(q, rng)])
    lam = 1e-3
    r = res(q)
    for _ in range(200):
        J = np.zeros((6, 5))
        for k in range(5):
            dq = np.zeros(5); dq[k] = 1e-5; J[:, k] = (res(q + dq) - r) / 1e-5
        qn = clip(q + np.linalg.solve(J.T @ J + lam * np.eye(5), -J.T @ r))
        rn = res(qn)
        if rn @ rn < r @ r:
            q, r, lam = qn, rn, max(lam / 3, 1e-7)
        else:
            lam *= 4
    return q, float(np.linalg.norm(res(q)[:3]))

def legs(lq, rq):
    """capsules: (p0, p1, radius) for thighs and shins, feet as points (centre, half sizes)."""
    out = []
    for s, q in (("l", lq), ("r", rq)):
        fk(s, q)
        hip, knee, ank = d.body(f"{s}_thigh").xpos.copy(), d.body(f"{s}_shin").xpos.copy(), d.body(f"{s}_foot").xpos.copy()
        out.append((s + "_thigh", hip, knee, 0.06)); out.append((s + "_shin", knee, ank, 0.045))
        g = d.geom(f"{s}_foot"); out.append((s + "_foot", g.xpos.copy() + g.xmat.reshape(3,3) @ np.array([-0.1, 0, 0]), g.xpos.copy() + g.xmat.reshape(3,3) @ np.array([0.1, 0, 0]), 0.035))
    return out

if __name__ == "__main__":
    for s, x, y in (("l", 0.34, 0.196), ("r", -0.18, -0.273), ("l", 0.45, 0.22), ("r", -0.35, -0.3), ("l", 0.0, 0.3)):
        q, err = ik(s, x, y)
        print(s, x, y, q.round(3), round(err, 4))
