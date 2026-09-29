"""Reach of the palm with a flexed / twisted trunk on the v3 body's own kinematics.

    .venv/bin/python scratchpad/btl2/reach2.py

For a set of (spine flexion, spine rotation), a palm point (x, y, z) and a palm normal tilted `a` rad from
straight down toward a horizontal direction u, solves the arm IK (six joints, model joint limits) from several
seeds and prints the position error (cm) of the best.  Left hand, left lead (positive y is the lead side;
spine_rot positive turns the lead-side shoulder back, as st_twist).
"""
import itertools
import sys

import mujoco
import numpy as np

sys.path.insert(0, "playground")
sys.path.insert(0, "playground/tasks")
from dribble_v3 import DribbleV3Task  # noqa: E402

t = DribbleV3Task()
m = mujoco.MjModel.from_xml_string(t.xml(t.builder()))
d = mujoco.MjData(m)
t.reset(m, d)
ARM = ("shoulder_flex", "shoulder_abd", "shoulder_rot", "elbow", "wrist_flex", "wrist_dev")
SEEDS = ([0.55, 0.05, -0.5, 1.4, -0.05, 0.1], [0.2, 0.4, -0.3, 0.6, 0.3, 0.0], [0.8, 0.6, -1.0, 1.0, 0.0, 0.0],
         [0.0, 0.2, 0.0, 1.0, 0.0, 0.0], [0.0, 0.3, 0.8, 0.3, 0.0, 0.0], [-0.2, 0.2, 1.2, 0.4, -0.3, 0.0])


def tilt(u, a):
    n = np.array([u[0] * np.sin(a), u[1] * np.sin(a), -np.cos(a)])
    return n / np.linalg.norm(n)


def ik(side, target, normal, seed, spine, rot, w=0.5):
    d.joint("spine_flex").qpos[0] = spine
    d.joint("spine_rot").qpos[0] = rot
    adr = [m.jnt_qposadr[m.joint(side + "_" + j).id] for j in ARM]
    rng = [m.jnt_range[m.joint(side + "_" + j).id] for j in ARM]
    pc = np.array([-0.018, 0.0, -0.12])

    def res(q):
        d.qpos[adr] = q
        mujoco.mj_kinematics(m, d)
        h = d.body(side + "_hand")
        R = h.xmat.reshape(3, 3)
        return np.concatenate([h.xpos + R @ pc - target, w * (-R[:, 0] - normal)])

    q = np.array(seed, float)
    lam = 1e-3
    r = res(q)
    for _ in range(120):
        J = np.zeros((6, 6))
        for k in range(6):
            dq = np.zeros(6)
            dq[k] = 1e-5
            J[:, k] = (res(q + dq) - r) / 1e-5
        qn = q + np.linalg.solve(J.T @ J + lam * np.eye(6), -J.T @ r)
        qn = np.array([np.clip(v, lo + 0.01, hi - 0.01) for v, (lo, hi) in zip(qn, rng)])
        rn = res(qn)
        if rn @ rn < r @ r:
            q, r, lam = qn, rn, lam / 3
        else:
            lam *= 4
    res(q)
    return float(np.linalg.norm(r[:3])), float(np.linalg.norm(r[3:]) / w), q


def best(side, target, n, spine, rot):
    return min((ik(side, target, n, s, spine, rot) for s in SEEDS), key=lambda r: r[0] + 0.1 * r[1])


def main():
    side = "l"
    print("left hand, palm point error in cm (orientation error rad) ; u = toward the other hand (-y), tilt 0.7 rad")
    for spine, rot in ((0.55, 0.55), (0.55, 0.9), (0.35, 0.55), (0.35, 0.0), (0.2, 0.0), (0.2, 0.55), (0.05, 0.0)):
        print(f"spine {spine} rot {rot}")
        for z in (0.85, 0.95, 1.05):
            row = []
            for x in (-0.15, -0.05, 0.05, 0.15, 0.25, 0.35):
                for y in (0.35,):
                    n = tilt(np.array([0.0, -1.0]), 0.7)
                    target = np.array([x - 0.12 * n[0], y - 0.12 * n[1], z])
                    e, oe, q = best(side, target, n, spine, rot)
                    row.append(f"x{x:+.2f}:{100 * e:4.1f}({oe:.2f})")
            print(f"  z {z}: " + "  ".join(row))


if __name__ == "__main__":
    main()
