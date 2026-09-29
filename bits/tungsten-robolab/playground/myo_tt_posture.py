"""myo_tt_posture.py: reachable arm postures for the MyoChallenge TT model (round 6): kinematics of the pad
with a measured grasp, the static muscle activations that hold a posture, and the arm's clearance from the thorax.

  .venv-myo/bin/python playground/myo_tt_posture.py check q1,..,q8
  .venv-myo/bin/python playground/myo_tt_posture.py opt --x -0.3 --wx 0.1 --y -0.15 --z 0.29 --clear 0.04 --lo=... --hi=... --q0 ... --fix 4,5,6,7

q = elv_angle, shoulder_elv, shoulder_rot, elbow_flexion, pro_sup, deviation, flexion, axial_rotation (rad).
Set OMP_NUM_THREADS=1 (the solver is tiny; BLAS threads only add load).


Model helpers (import): Stat(seed) -> object with
  .set(q8, trunk=(fe, lb))   set servo joints (elv, sh_elv, sh_rot, elbow, pro_sup, dev, flex, axial) + trunk,
                             equality-slaved joints from their polynomials, pelvis at the reset pose
  .pad(grasp_R, grasp_p)     pad centre and normal (world) for the paddle held at that grasp (S_grasp frame)
  .acts(q8)                  min-norm arm activations (32 arm muscles, 0..1) holding the posture still against
                             gravity + passive forces, and the residual torque (N m) per servo joint
"""
import json
import os
import sys
import numpy as np

os.environ.setdefault("TT_ENV", "P2")
ARM = ["DELT1", "DELT2", "DELT3", "SUPSP", "INFSP", "SUBSC", "TMIN", "TMAJ", "PECM1", "PECM2", "PECM3", "LAT1", "LAT2",
       "LAT3", "CORB", "TRIlong", "TRIlat", "TRImed", "ANC", "SUP", "BIClong", "BICshort", "BRA", "BRD", "ECRL", "ECRB",
       "ECU", "FCR", "FCU", "PL", "PT", "PQ"]
SERVO = ["elv_angle", "shoulder_elv", "shoulder_rot", "elbow_flexion", "pro_sup", "deviation", "flexion", "axial_rotation"]


class Stat:
    def __init__(self, seed=300200):
        import gymnasium as gym
        import myosuite  # noqa: F401
        import mujoco
        self.mj = mujoco
        env = gym.make("myoChallengeTableTennisP2-v0")
        u = env.unwrapped
        env.reset(seed=seed)
        self.m = u.mj_model
        self.d = mujoco.MjData(self.m)
        self.d.qpos[:] = u.mj_data.qpos
        self.q0 = self.d.qpos.copy()
        m = self.m
        self.site = m.site("S_grasp").id
        self.pbody = m.body("paddle").id
        g = m.geom("pad").id
        self.pad_pos = m.geom_pos[g].copy()
        self.pad_quat = m.geom_quat[g].copy()
        R = np.zeros(9)
        mujoco.mju_quat2Mat(R, self.pad_quat)
        self.pad_R = R.reshape(3, 3)
        self.jq = {n: m.jnt_qposadr[m.joint(n).id] for n in SERVO + ["flex_extension", "lat_bending"]}
        self.jd = {n: m.jnt_dofadr[m.joint(n).id] for n in SERVO + ["flex_extension", "lat_bending"]}
        # equality-slaved joints: (dependent qpos adr, dependent dof adr, master qpos adr or None, coefficients)
        self.eqs = []
        for e in range(m.neq):
            if m.eq_type[e] == mujoco.mjtEq.mjEQ_JOINT and m.eq_active0[e]:
                j1, j2 = m.eq_obj1id[e], m.eq_obj2id[e]
                self.eqs.append((m.jnt_qposadr[j1], m.jnt_dofadr[j1], m.jnt_qposadr[j2] if j2 >= 0 else None,
                                 m.jnt_dofadr[j2] if j2 >= 0 else None, np.array(m.eq_data[e][:5])))
        self.arm_ids = [m.actuator(n).id for n in ARM]

    def set(self, q8, trunk=(0.05, 0.0)):
        d = self.d
        d.qpos[:] = self.q0
        for n, v in zip(SERVO, q8):
            d.qpos[self.jq[n]] = v
        d.qpos[self.jq["flex_extension"]] = trunk[0]
        d.qpos[self.jq["lat_bending"]] = trunk[1]
        for _ in range(2):
            for qa, _, qm, _, c in self.eqs:
                x = d.qpos[qm] if qm is not None else 0.0
                d.qpos[qa] = c[0] + c[1] * x + c[2] * x * x + c[3] * x ** 3 + c[4] * x ** 4
        d.qvel[:] = 0.0
        self.mj.mj_kinematics(self.m, d)
        self.mj.mj_comPos(self.m, d)

    def palm(self):
        d = self.d
        return d.site_xpos[self.site].copy(), d.site_xmat[self.site].reshape(3, 3).copy()

    def pad(self, grasp_R, grasp_p):
        ps, Rs = self.palm()
        Rp = Rs @ np.array(grasp_R).reshape(3, 3)
        pp = ps + Rs @ np.array(grasp_p)
        c = pp + Rp @ self.pad_pos
        n = (Rp @ self.pad_R)[:, 2]
        if n[0] > 0:
            n = -n
        return c, n

    def G(self):
        """nv x 8: all dof velocities per unit servo-joint velocity (slaved joints by their polynomial's slope)."""
        m, d = self.m, self.d
        G = np.zeros((m.nv, len(SERVO)))
        col = {self.jd[n]: k for k, n in enumerate(SERVO)}
        for n, k in zip(SERVO, range(len(SERVO))):
            G[self.jd[n], k] = 1.0
        for qa, da, qm, dm, c in self.eqs:
            if dm is None or dm not in col:
                continue
            x = d.qpos[qm]
            G[da, col[dm]] += c[1] + 2 * c[2] * x + 3 * c[3] * x * x + 4 * c[4] * x ** 3
        return G

    def acts(self, q8, trunk=(0.05, 0.0), cap=1.0, joints=range(7)):
        from scipy.optimize import lsq_linear
        mj, m, d = self.mj, self.m, self.d
        self.set(q8, trunk)
        d.act[:] = 0.0
        mj.mj_forward(m, d)
        bias = d.qfrc_bias.copy()
        passive = d.qfrc_passive.copy()
        F0 = d.actuator_force.copy()
        d.act[:] = 1.0
        mj.mj_forward(m, d)
        F1 = d.actuator_force.copy()
        gain = F1 - F0
        # dense moment rows for the arm actuators
        Mo = np.zeros((m.nu, m.nv))
        for i in range(m.nu):
            a, n = d.moment_rowadr[i], d.moment_rownnz[i]
            Mo[i, d.moment_colind[a:a + n]] = d.actuator_moment[a:a + n]
        G = self.G()
        # generalised force of all actuators at zero activation (passive muscle forces)
        tau_p = G.T @ (Mo.T @ F0 + passive)
        need = G.T @ bias - tau_p
        A = G.T @ (Mo[self.arm_ids].T * gain[self.arm_ids])
        J = list(joints)
        A, need = A[J], need[J]
        mu = 1e4
        Aug = np.vstack([np.sqrt(mu) * A, np.eye(A.shape[1])])
        rhs = np.r_[np.sqrt(mu) * need, np.zeros(A.shape[1])]
        sol = lsq_linear(Aug, rhs, bounds=(0.0, cap))
        a = sol.x
        return a, A @ a - need, need



# ---- posture search -------------------------------------------------------------

GR = {"grasp_R": [-0.4077, -0.7361, -0.5546, 0.9071, -0.3644, -0.2215, -0.0593, -0.5778, 0.8113], "grasp_p": [0.0451, -0.0416, -0.002]}  # the backhand's grasp at contact (paddle pose in the S_grasp frame, median of round-5 hits)
LO = np.array([-1.6, 0.0, -1.5, 0.3, -1.5, -0.17, -0.78, -0.6])
HI = np.array([2.2, 2.0, 2.0, 2.2, 1.5, 0.43, 0.78, 0.6])


def state(s, q, trunk=(-0.10, 0.09)):
    s.set(q, trunk)
    c, n = s.pad(GR["grasp_R"], GR["grasp_p"])
    pel = s.d.xpos[s.m.body("pelvis").id].copy()
    return c - pel, n


ARMG = ["humerus_coll", "radius_coll"]
TORG = ["thorax_coll0", "thorax_coll1", "thorax_coll2", "thorax_coll3"]


def clearance(s):
    """Least distance (m) of the upper arm and forearm collision capsules to the thorax's."""
    import mujoco
    m, d = s.m, s.d
    if not hasattr(s, "_pairs"):
        s._pairs = set()
        arm = {m.geom(n).id for n in ARMG}
        for i in range(m.npair):
            if int(m.pair_geom1[i]) in arm or int(m.pair_geom2[i]) in arm:
                s._pairs.add((int(m.pair_geom1[i]), int(m.pair_geom2[i])))
        s._margin = m.pair_margin.copy()
        m.pair_margin[:] = 0.1
    mujoco.mj_collision(m, d)
    best = 0.1
    for i in range(d.ncon):
        c = d.contact[i]
        if (int(c.geom1), int(c.geom2)) in s._pairs or (int(c.geom2), int(c.geom1)) in s._pairs:
            best = min(best, float(c.dist))
    return best


def report(s, q):
    a, res, need = s.acts(q, trunk=(-0.10, 0.09))
    rel, n = state(s, q)
    print("q", np.round(q, 3).tolist())
    print("  pad - pelvis", rel.round(3), "normal", n.round(3), "clearance %.3f" % clearance(s))
    print("  static need (N m)", need.round(1), " acts max %.2f  sum sq %.3f" % (a.max(), float(a @ a)))
    print("  top", [(n_, round(float(x), 2)) for x, n_ in sorted(zip(a, ARM), reverse=True)[:8]])
    return a


def main():
    import argparse
    from scipy.optimize import minimize
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd")
    ap.add_argument("q", nargs="?")
    ap.add_argument("--x", type=float, default=-0.2)
    ap.add_argument("--y", type=float, default=-0.2)
    ap.add_argument("--z", type=float, default=0.25)
    ap.add_argument("--wy", type=float, default=5.0)
    ap.add_argument("--n", default="-0.985,0.11,0.095")
    ap.add_argument("--wa", type=float, default=1.0)
    ap.add_argument("--wr", type=float, default=0.01)
    ap.add_argument("--q0", default="0.242,0.409,0.623,1.878,0.297,-0.039,0.363,0.206")
    ap.add_argument("--fix", default="", help="indices held at q0 (e.g. 7 for the trunk)")
    ap.add_argument("--lo", default="")
    ap.add_argument("--clear", type=float, default=0.03)
    ap.add_argument("--wx", type=float, default=1.0)
    ap.add_argument("--hi", default="")
    a = ap.parse_args()
    s = Stat()
    if a.cmd == "check":
        report(s, np.array([float(x) for x in a.q.split(",")]))
        return
    global LO, HI
    if a.lo:
        LO = np.array([float(x) for x in a.lo.split(",")])
    if a.hi:
        HI = np.array([float(x) for x in a.hi.split(",")])
    q0 = np.array([float(x) for x in a.q0.split(",")])
    nt = np.array([float(x) for x in a.n.split(",")])
    nt = nt / np.linalg.norm(nt)
    fix = [int(i) for i in a.fix.split(",") if i]
    free = [i for i in range(8) if i not in fix]

    def full(x):
        q = q0.copy()
        q[free] = x
        return q

    def cost(x):
        q = np.clip(full(x), LO, HI)
        rel, n = state(s, q)
        act, res, _ = s.acts(q, trunk=(-0.10, 0.09))
        c = 100.0 * (a.wx * (rel[0] - a.x) ** 2 + a.wy * 0.1 * (rel[1] - a.y) ** 2 + (rel[2] - a.z) ** 2) * 10
        c += 100.0 * float(np.sum((n - nt) ** 2))
        c += a.wa * float(act @ act) + 10.0 * float(res @ res) / 100.0
        c += a.wr * float(np.sum((q - q0) ** 2))
        c += 1e4 * max(0.0, a.clear - clearance(s)) ** 2
        return c

    best = None
    for start in range(3):
        x0 = q0[free] + (0 if start == 0 else np.random.default_rng(start).normal(0, 0.15, len(free)))
        r = minimize(cost, x0, method="Powell", bounds=list(zip(LO[free], HI[free])), options={"maxiter": 4000, "xtol": 1e-3, "ftol": 1e-5})
        print("start", start, "cost %.4f" % r.fun, flush=True)
        if best is None or r.fun < best.fun:
            best = r
    q = np.clip(full(best.x), LO, HI)
    act = report(s, q)
    print("acts:", ",".join(f"b7_a{i}={v:.4f}" for i, v in enumerate(act)))
    names = ["bh_elv", "bh_sh_elv", "bh_sh_rot", "bh_elbow", "bh_pro_sup", "bh_dev", "bh_wflex", "bh_trunk_ar"]
    print(",".join(f"{n_}={v:.4f}" for n_, v in zip(names, q)))


if __name__ == "__main__":
    main()
