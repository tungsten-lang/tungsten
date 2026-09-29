"""Computed muscle control of the table-tennis arm, prototype in the bridge (round 10).

The skill turns a joint-space posture into muscle thresholds through an additive length model and a saturating
stretch reflex: the arm reaches 0.2-0.6 rad off its command and the pad's pitch varies 9-10 deg serve to serve.
Here the arm's 32 muscles are driven instead by computed muscle control: the model's own quantities (the
muscles' force-length-velocity gain and passive force from MuJoCo's muscle model, moment arms with the
equality-slaved shoulder girdle folded onto its masters, the mass matrix and bias forces of the 70-dof
model), a joint-space computed-torque law on the seven arm joints

    tau = M_aa (qdd_ref + Kp e + Kd ed + Ki int e) + M_ab qdd_base + bias_a - tau_passive_a

and a bounded least-squares allocation of the muscles' active forces (minimum activation, a small
co-contraction floor `a0` for stiffness), with the excitation leading the first-order activation dynamics.
It replaces the controller's activations for the arm muscles only (trunk, hand and pelvis stay the skill's).

    CMCSim(task, params, controller, seed, plan=...)  # a MyoSim whose tick() overrides the arm muscles
"""

import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import mujoco  # noqa: E402

from myo_bridge import MyoSim  # noqa: E402

ARM_MUSCLES = ("DELT1", "DELT2", "DELT3", "SUPSP", "INFSP", "SUBSC", "TMIN", "TMAJ", "PECM1", "PECM2", "PECM3",
               "LAT1", "LAT2", "LAT3", "CORB", "TRIlong", "TRIlat", "TRImed", "ANC", "SUP", "BIClong", "BICshort",
               "BRA", "BRD", "ECRL", "ECRB", "ECU", "FCR", "FCU", "PL", "PT", "PQ")
ARM_JOINTS = ("elv_angle", "shoulder_elv", "shoulder_rot", "elbow_flexion", "pro_sup", "deviation", "flexion")


def min_jerk(x0, x1, T, t):
    """Position, velocity, acceleration of the minimum-jerk path x0 -> x1 over T at time t (rest to rest)."""
    if T <= 0:
        return x1, 0 * x1, 0 * x1
    s = min(max(t / T, 0.0), 1.0)
    p = 10 * s ** 3 - 15 * s ** 4 + 6 * s ** 5
    v = (30 * s ** 2 - 60 * s ** 3 + 30 * s ** 4) / T
    a = (60 * s - 180 * s ** 2 + 120 * s ** 3) / T ** 2
    if t >= T:
        v = a = 0.0
    d = x1 - x0
    return x0 + d * p, d * v, d * a


class ArmCMC:
    def __init__(self, sim, kp=400.0, kd=40.0, ki=0.0, a0=0.03, w_track=1e3, lead=1.0):
        m = sim.m
        self.m = m
        self.kp, self.kd, self.ki, self.a0, self.w, self.lead = kp, kd, ki, a0, w_track, lead
        self.act_ids = [m.actuator(n).id for n in ARM_MUSCLES]
        self.pos_in_muscles = [sim.muscle_ids.index(i) for i in self.act_ids]
        self.actadr = [int(m.actuator_actadr[i]) for i in self.act_ids]
        self.joint_ids = [m.joint(n).id for n in ARM_JOINTS]
        self.qadr = [int(m.jnt_qposadr[j]) for j in self.joint_ids]
        self.dof = [int(m.jnt_dofadr[j]) for j in self.joint_ids]
        # folding: dq_full = F dq_master (equality-slaved joints follow their masters)
        self.deps = []
        for j in self.joint_ids:
            deps = []
            for e in range(m.neq):
                if m.eq_type[e] == mujoco.mjtEq.mjEQ_JOINT and m.eq_obj2id[e] == j:
                    deps.append((int(m.jnt_dofadr[m.eq_obj1id[e]]), int(m.jnt_qposadr[j]), np.array(m.eq_data[e][:5])))
            self.deps.append(deps)
        self.nv = m.nv
        self.Mfull = np.zeros((m.nv, m.nv))
        self.int_e = np.zeros(len(ARM_JOINTS))
        self.qd_prev = None
        self.tau_prev = None

    def fold(self, d):
        F = np.zeros((self.nv, len(self.joint_ids)))
        for k, dof in enumerate(self.dof):
            F[dof, k] = 1.0
            for sdof, qa, c in self.deps[k]:
                x = d.qpos[qa]
                F[sdof, k] = c[1] + x * (2 * c[2] + x * (3 * c[3] + 4 * c[4] * x))
        return F

    def muscle_terms(self, d):
        m = self.m
        L = d.actuator_length[self.act_ids]
        V = d.actuator_velocity[self.act_ids]
        g = np.array([mujoco.mju_muscleGain(L[k], V[k], m.actuator_lengthrange[i], m.actuator_acc0[i], m.actuator_gainprm[i][:9])
                      for k, i in enumerate(self.act_ids)])
        b = np.array([mujoco.mju_muscleBias(L[k], m.actuator_lengthrange[i], m.actuator_acc0[i], m.actuator_biasprm[i][:9])
                      for k, i in enumerate(self.act_ids)])
        # moments folded onto the master joints
        mom = np.zeros((m.nu, m.nv))
        mujoco.mju_sparse2dense(mom, d.actuator_moment, d.moment_rownnz, d.moment_rowadr, d.moment_colind)
        return g, b, mom[self.act_ids]

    def step(self, sim, qref, qdref, qddref, dt=0.01):
        m, d = self.m, sim.d
        F = self.fold(d)
        q = np.array([d.qpos[a] for a in self.qadr])
        qd = np.array([d.qvel[a] for a in self.dof])
        mujoco.mj_fullM(m, self.Mfull, d.qM)
        M = self.Mfull
        Maa = F.T @ M @ F
        bias = F.T @ d.qfrc_bias
        pas = F.T @ d.qfrc_passive
        g, b, Rfull = self.muscle_terms(d)
        R = Rfull @ F                               # (32 x 7): d muscle length / d master joint
        # measured base + arm accelerations (finite difference of the velocities over the last step)
        qdd_all = np.zeros(self.nv)
        if self.qd_prev is not None:
            qdd_all = (d.qvel - self.qd_prev) / dt
        self.qd_prev = d.qvel.copy()
        # coupling to what is not commanded: M (qdd_meas) with the arm's own rows replaced by the command
        Fqdd = np.linalg.pinv(F) @ qdd_all          # the arm masters' measured accelerations
        rest = M @ qdd_all - M @ (F @ Fqdd)         # inertial load of the non-arm dofs (base, fingers) on the arm rows
        rest_a = F.T @ rest
        e = qref - q
        self.int_e = np.clip(self.int_e + e * dt, -0.2, 0.2)
        qdd_cmd = qddref + self.kp * e + self.kd * (qdref - qd) + self.ki * self.int_e
        tau_musc = Maa @ qdd_cmd + rest_a + bias - pas          # what the muscles must supply (active + passive)
        tau_act = tau_musc - R.T @ b                            # what the ACTIVE forces must supply
        G = R.T * g[None, :]                                    # (7 x 32): joint torque per unit activation
        # min |a - a0|^2 + w |G a - tau_act|^2 with 0 <= a <= 1
        from scipy.optimize import lsq_linear
        A = np.vstack([np.sqrt(self.w) * G, np.eye(len(g))])
        y = np.concatenate([np.sqrt(self.w) * tau_act, self.a0 * np.ones(len(g))])
        a = lsq_linear(A, y, bounds=(0.0, 1.0), method="bvls", max_iter=60).x
        act_now = np.array([d.act[adr] for adr in self.actadr])
        # excitation leading the first-order activation dynamics
        tau_c = np.where(a > act_now, 0.01 * (0.5 + 1.5 * act_now), 0.04 / (0.5 + 1.5 * act_now))
        u = np.clip(act_now + self.lead * tau_c * (a - act_now) / dt, 0.0, 1.0)
        self.last = {"q": q, "qd": qd, "e": e, "tau_act": tau_act, "a": a, "achieved": G @ a - tau_act}
        return u


class CMCSim(MyoSim):
    """A MyoSim whose arm muscles are driven by ArmCMC tracking `plan(t, sim) -> (qref, qdref, qddref)`."""

    def __init__(self, task, params=None, controller=None, seed=None, plan=None, cmc_kw=None, **kw):
        super().__init__(task, params=params, controller=controller, seed=seed, **kw)
        if not hasattr(self, "_tt_jac"):
            task.hand_jacobian(self)
        self.cmc = ArmCMC(self, **(cmc_kw or {}))
        self.plan = plan
        self.cmc_on = plan is not None

    def tick(self):
        act, c = super().tick()
        if self.cmc_on:
            qref, qdref, qddref = self.plan(self.d.time, self)
            u = self.cmc.step(self, qref, qdref, qddref)
            act = act.copy()
            for k, pos in enumerate(self.cmc.pos_in_muscles):
                act[pos] = u[k]
            if not hasattr(self, "cmc_log"):
                self.cmc_log = []
            L = self.cmc.last
            self.cmc_log.append((self.d.time, L["e"].copy(), L["achieved"].copy(), float(L["a"].mean()), L["q"].copy()))
        return act, c
