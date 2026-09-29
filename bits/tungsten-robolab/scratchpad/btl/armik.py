import sys, numpy as np, mujoco
sys.path.insert(0, "playground"); sys.path.insert(0, "playground/tasks")
from dribble_v3 import DribbleV3Task
t = DribbleV3Task(); m = mujoco.MjModel.from_xml_string(t.xml(t.builder())); d = mujoco.MjData(m); t.reset(m, d)
ARM = ("shoulder_flex", "shoulder_abd", "shoulder_rot", "elbow", "wrist_flex", "wrist_dev")
def ik(side, target, normal, seed, spine=0.55, reg=2e-3, w=0.5):
    d.joint("spine_flex").qpos[0] = spine
    adr = [m.jnt_qposadr[m.joint(side + "_" + j).id] for j in ARM]
    rng = [m.jnt_range[m.joint(side + "_" + j).id] for j in ARM]
    pc = np.array([-0.018, 0.0, -0.12])
    def res(q):
        d.qpos[adr] = q; mujoco.mj_kinematics(m, d)
        h = d.body(side + "_hand"); R = h.xmat.reshape(3, 3)
        return np.concatenate([h.xpos + R @ pc - target, w * (-R[:, 0] - normal)])
    q = np.array(seed, float)
    for _ in range(200):
        r = res(q); J = np.zeros((6, 6))
        for k in range(6):
            dq = np.zeros(6); dq[k] = 1e-5; J[:, k] = (res(q + dq) - r) / 1e-5
        q = q + np.linalg.solve(J.T @ J + reg * np.eye(6), -J.T @ r - reg * (q - seed))
        q = np.array([np.clip(v, lo + 0.02, hi - 0.02) for v, (lo, hi) in zip(q, rng)])
    r = res(q)
    return q, float(np.linalg.norm(r[:3])), d.body(side + "_forearm").xpos.copy(), d.body(side + "_upper_arm").xpos.copy()
def tilt(u, a):
    n = np.array([u[0] * np.sin(a), u[1] * np.sin(a), -np.cos(a)]); return n / np.linalg.norm(n)
if __name__ == "__main__":
    R, L = np.array([0.2, -0.38]), np.array([-0.1, 0.46])
    for side, sp, ot in (("l", L, R), ("r", R, L)):
        u = (ot - sp) / np.linalg.norm(ot - sp)
        for z in (1.05, 0.95, 0.85):
            n = tilt(u, 0.35); target = np.array([sp[0] - 0.12 * n[0], sp[1] - 0.12 * n[1], z])
            for seed in ([0.55, 0.05, -0.5, 1.4, -0.05, 0.1], [-0.3, 0.3, 0.0, 0.8, 0.0, 0.0], [0.0, 0.6, 0.5, 1.2, 0.0, 0.0], [0.2, 0.4, -0.3, 0.6, 0.3, 0.0]):
                q, err, elbow, sh = ik(side, target, n, seed)
                print(side, z, "seed", seed[:4], "err", round(err, 3), "q", q.round(2), "elbow z", round(elbow[2], 2), "elbow xy", elbow[:2].round(2))
