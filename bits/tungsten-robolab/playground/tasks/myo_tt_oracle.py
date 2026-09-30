"""MyoChallenge 2025 table tennis, ORACLE DIAGNOSTICS on the OFFICIAL body (agent T3, 29-30 Sep 2026).

LABEL. Everything switched on here is a LABELLED DIAGNOSTIC ORACLE: it uses information or forces no real controller has (the pelvis's own final
position from a first pass, joint torques that make the arm follow its commanded posture, a kinematic paddle). Its results are never to be compared
with the official trials (tt_p1, tt_p2, tt_p2_300, tt_p2_backhand) and nothing here touches a champion, a param file or an arena trial. The rule, the
serve sets and the decision thresholds are in scratchpad/tt3/LOG.md (pre-registered 2026-09-29 23:53, before any oracle ran).

SWITCH. env var MYO_TT_ORACLE = comma list of modes; unset / empty / "off" = the OFFICIAL task (this module then installs nothing at all, so a rollout is
byte-identical to tasks/myo_tt.py's; proved by scratchpad/tt3/identity.py). Run through tt_fast / tt_eval with TT_TASK=myo_tt_oracle:

  rec   record only: per control tick the commanded arm posture (q_fit: the 7 arm joints' angles whose additive-length-model contractions, the controller's own
        posture -> contraction map (lib/robolab/skills/myo_tt.w Pose#apply_geometry), best fit the 32 arm muscles' emitted contraction targets, plus the fitted
        co-contraction) and the reached posture, into TT3_LOG/<seed>.npz. Nothing is changed: every metric equals the official task's.
  o1    SETTLED PELVIS (two-pass). Pass 1 = a TT_SAVE_LOG run of the champion (dir TT3_PASS1, default out/tt3/logs_o0) gives each serve's contact time tc (closest
        approach of the ball to the pad for a miss) and the pelvis slides' position there. Pass 2 (this run) replays the seed and drives the two pelvis position
        actuators on a minimum-jerk reference from the reset position to that position, arriving by tc - margin (cfg o1_margin, 0.15 s) and held: zero pelvis velocity at contact.
        The command adds the force the reference needs, (m a + c v) / kp, as the controller's own set_pelvis does.
  o2    IDEAL ARM: the 7 arm joints are held ON a reference (an infinite-gain, zero-lag joint servo, realised kinematically after every physics substep; the torque it takes is estimated) that follows a reference built from the controller's OWN
        commanded posture q_fit: q_ref = qbar_s[i] + g (q_fit - fbar_s[i]) with, per side s and tick i, the champion's MEAN reached posture qbar and mean commanded posture fbar
        over set A's serves (a record-only run) and g the per-joint regression slope of its reached deviation on its commanded deviation (scratchpad/tt3/calibrate2.py,
        cfg o2_cal). The champion's mean response (the operating point its parameters were practised around: the plant attenuates every asked change to 0.2-0.6, so
        "reached = asked" taken literally would move the pad far from where the parameters expect it) and its linear response to what each serve asks are kept; the scatter
        that the command does not explain (pelvis-induced arm swing, joint ringing, grip drift in the joints) is removed. Muscles, grip and pelvis are the champion's.
  o3    o1 + o2.
  o4    KINEMATIC PADDLE: from t_on the paddle body is overwritten each physics substep to a planned pose: the pad centre on the line P + v (t - t_hit), the pad normal n
        (plan file TT3_PLAN: {seed: {"t_hit", "P", "n", "v"}}, built offline from the pass-1 record by scratchpad/tt3/make_plans.py). The hand's contacts with the
        paddle are switched off while it is puppeted and the ball meets only the pad disc, the table halves, the net and the floor (contype/conaffinity bits, see
        Oracle.apply_geoms; restored at the episode's end: an arm left where the champion had it must not catch the rebound); the ball still hits
        the pad through the environment's own contact model, and `solved` is the environment's.

Extra metrics only when a mode is on (off adds none). TT3_CFG = a JSON dict of the modes' options.
"""

import json
import os
import sys

import numpy as np

_PLAYGROUND = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _PLAYGROUND not in sys.path:
    sys.path.insert(0, _PLAYGROUND)

from tasks.myo_tt import MyoTTTask  # noqa: E402

MODES = {m for m in os.environ.get("MYO_TT_ORACLE", "").replace(" ", "").lower().split(",") if m and m != "off"}
if "o3" in MODES:
    MODES |= {"o1", "o2"}
CFG = json.loads(os.environ.get("TT3_CFG", "{}") or "{}")
PASS1 = os.environ.get("TT3_PASS1", "out/tt3/logs_o0")
LOGDIR = os.environ.get("TT3_LOG", "")
PLAN = os.environ.get("TT3_PLAN", "")

ARM7 = ("elv_angle", "shoulder_elv", "shoulder_rot", "elbow_flexion", "pro_sup", "deviation", "flexion")
TRUNK3 = ("flex_extension", "lat_bending", "axial_rotation")
ARM_MUSCLES = MyoTTTask.ARM_MUSCLES
# [dependent, independent, coefficient] (myo_tt.w MyoTTKin.couplings)
COUPLINGS = [("Abs_r3", "flex_extension", 0.6429), ("L4_L5_FE", "flex_extension", 0.185), ("L3_L4_FE", "flex_extension", 0.204),
             ("L2_L3_FE", "flex_extension", 0.231), ("L1_L2_FE", "flex_extension", 0.255), ("L4_L5_LB", "lat_bending", 0.1811),
             ("L3_L4_LB", "lat_bending", 0.2453), ("L2_L3_LB", "lat_bending", 0.2501), ("L1_L2_LB", "lat_bending", 0.188),
             ("L4_L5_AR", "axial_rotation", 0.0378), ("L3_L4_AR", "axial_rotation", 0.0378), ("L2_L3_AR", "axial_rotation", 0.0311),
             ("L1_L2_AR", "axial_rotation", 0.0289), ("sternoclavicular_r2", "shoulder_elv", -0.242),
             ("sternoclavicular_r3", "shoulder_elv", 0.1025), ("unrotscap_r2", "shoulder_elv", 0.242),
             ("unrotscap_r3", "shoulder_elv", -0.1025), ("acromioclavicular_r1", "shoulder_elv", 0.178),
             ("acromioclavicular_r2", "shoulder_elv", -0.049), ("acromioclavicular_r3", "shoulder_elv", 0.396),
             ("unrothum_r1", "shoulder_elv", -0.178), ("unrothum_r2", "shoulder_elv", 0.049), ("unrothum_r3", "shoulder_elv", -0.396),
             ("shoulder1_r2", "elv_angle", -1.0)]

_PRISTINE = {}
TAU_MAX = float(CFG.get("o2_taumax", 500.0))
O4_GEOMS = ("pad", "handle", "pingpong", "coll_own_half", "coll_opponent_half", "coll_net", "ground")


class ArmFit:
    """The controller's posture -> contraction map (the additive length model of lib/robolab/body.w Geometry, as Pose#apply_geometry uses it) inverted on the
    32 arm muscles' emitted contraction targets: q_fit (the 7 arm joints) and s (the co-contraction, each muscle commanded s/2 shorter than its posture needs)."""

    def __init__(self, sim, trunk):
        joints = sim.joints                                   # (jid, name, lo, hi, qref, qadr) per slot
        self.jn = [j[1] for j in joints]
        self.slot = {n: k for k, n in enumerate(self.jn)}
        self.nj = len(joints)
        self.qref = np.array([j[4] for j in joints], float)
        self.lo = np.array([j[2] for j in joints], float)
        self.hi = np.array([j[3] for j in joints], float)
        names = [mu.name for mu in sim.muscles]
        self.arm = [i for i, nm in enumerate(names) if nm in ARM_MUSCLES]
        self.lmin = np.array(sim.lr[self.arm, 0], float)
        self.lmax = np.array(sim.lr[self.arm, 1], float)
        self.rng = self.lmax - self.lmin
        self.lref = np.array(sim.lref)[self.arm].astype(float)
        self.tabs = []                                        # per slot: (rows, R (rows x S), value at qref)
        for k in range(self.nj):
            rows = [r for r, i in enumerate(self.arm) if k in sim.table[i]]
            if not rows:
                self.tabs.append(None)
                continue
            R = np.array([sim.table[self.arm[r]][k] for r in rows], float)
            self.tabs.append((np.array(rows), R, self._val(R, k, self.qref[k])))
        self.trunk = dict(zip(TRUNK3, trunk))
        # d qfull / d q7: joint j's own slot and the joints slaved to it
        self.dq = np.zeros((self.nj, 7))
        for j, n in enumerate(ARM7):
            if n in self.slot:
                self.dq[self.slot[n], j] = 1.0
            for dep, mas, coef in COUPLINGS:
                if mas == n and dep in self.slot:
                    self.dq[self.slot[dep], j] = coef
        self.x = None

    def _uv(self, R, k, q):
        S = R.shape[1]
        u = (q - self.lo[k]) / (self.hi[k] - self.lo[k]) * (S - 1)
        u = min(max(u, 0.0), S - 1.0)
        a = min(int(u), S - 2)
        return a, u - a, S

    def _val(self, R, k, q):
        a, t, _ = self._uv(R, k, q)
        return R[:, a] * (1 - t) + R[:, a + 1] * t

    def full(self, q7):
        qf = self.qref.copy()
        val = dict(zip(ARM7, q7))
        val.update(self.trunk)
        for n, v in val.items():
            if n in self.slot:
                qf[self.slot[n]] = v
        for dep, mas, coef in COUPLINGS:
            if dep in self.slot:
                qf[self.slot[dep]] = coef * val[mas]
        for n in ("Abs_t1", "Abs_t2"):
            if n in self.slot:
                qf[self.slot[n]] = 0.0
        return qf

    def model(self, q7):
        """contractions (32,) and their Jacobian over q7 (32 x 7) at the arm posture q7"""
        qf = self.full(q7)
        L = self.lref.copy()
        D = np.zeros((len(self.arm), self.nj))
        for k in range(self.nj):
            tb = self.tabs[k]
            if tb is None:
                continue
            rows, R, fref = tb
            a, t, S = self._uv(R, k, qf[k])
            L[rows] += R[:, a] * (1 - t) + R[:, a + 1] * t - fref
            if self.lo[k] < qf[k] < self.hi[k]:
                D[rows, k] = (R[:, a + 1] - R[:, a]) / ((self.hi[k] - self.lo[k]) / (S - 1))
        c = (self.lmax - L) / self.rng
        J = -(D @ self.dq) / self.rng[:, None]
        return c, J

    def solve(self, targets, x0=None, iters=4):
        cs = np.asarray(targets, float)[self.arm]
        x = self.x.copy() if (x0 is None and self.x is not None) else (np.r_[x0, 0.0] if x0 is not None else np.zeros(8))
        for _ in range(iters):
            c, J = self.model(x[:7])
            r = cs - c - 0.5 * x[7]
            A = np.hstack([J, 0.5 * np.ones((len(cs), 1))])
            dx = np.linalg.solve(A.T @ A + 1e-5 * np.eye(8), A.T @ r)
            dx[:7] = np.clip(dx[:7], -0.3, 0.3)
            x = x + dx
        c, _ = self.model(x[:7])
        res = float(np.sqrt(np.mean((cs - c - 0.5 * x[7]) ** 2)))
        self.x = x
        return x[:7].copy(), float(x[7]), res


def min_jerk(t, t0, T, q0, q1):
    """(position, velocity, acceleration) of the minimum-jerk path q0 -> q1 over [t0, t0 + T], held afterwards (arrays)"""
    tau = (t - t0) / T
    if tau <= 0.0:
        return q0.copy(), np.zeros_like(q0), np.zeros_like(q0)
    if tau >= 1.0:
        return q1.copy(), np.zeros_like(q0), np.zeros_like(q0)
    d = q1 - q0
    s = 10 * tau ** 3 - 15 * tau ** 4 + 6 * tau ** 5
    v = (30 * tau ** 2 - 60 * tau ** 3 + 30 * tau ** 4) / T
    a = (60 * tau - 180 * tau ** 2 + 120 * tau ** 3) / (T * T)
    return q0 + d * s, d * v, d * a


class Oracle:
    """Per-episode oracle state; installed on a MyoSim by MyoTTOracleTask.extra_sensors on its first call."""

    def __init__(self, sim):
        import mujoco
        self.mj = mujoco
        self.sim = sim
        self.robot = sim.u.robot
        self.m = self.robot.mj_model
        self.d = self.robot.mj_data
        self.seed = int(sim.seed)
        self.modes = set(MODES)
        self.dt = float(sim.u.dt)
        self.tick_i = 0
        self.log = []
        m = self.m
        self.pel_q = [int(m.jnt_qposadr[m.joint(n).id]) for n in ("pelvis_x", "pelvis_y")]
        self.pel_d = [int(m.jnt_dofadr[m.joint(n).id]) for n in ("pelvis_x", "pelvis_y")]
        self.arm_q = [int(m.jnt_qposadr[m.joint(n).id]) for n in ARM7]
        self.arm_d = [int(m.jnt_dofadr[m.joint(n).id]) for n in ARM7]
        self.pad_body = int(m.body("paddle").id)
        self.pad_q = int(m.jnt_qposadr[m.joint("paddle_freejoint").id])
        self.pad_d = int(m.jnt_dofadr[m.joint("paddle_freejoint").id])
        self.metrics = {}
        # pass-1 record (o1)
        self.rec = None
        if self.modes & {"o1"}:
            self.load_pass1()
        # the arm fit (rec, o2)
        self.fit = None
        self.q_ref = None
        self.qd_ref = np.zeros(7)
        self.q_ref0 = None
        self.qfit0 = None
        self.tau_peak = np.zeros(7)
        self.tau_sq = np.zeros(7)
        self.tau_tick = np.zeros(7)
        self.tau_n = 0
        self.q_prev = None
        self.q_own = None
        self.qd_last = np.zeros(7)
        self.qd_prev_tick = np.zeros(7)
        self.err_log = []
        if "o2" in self.modes and CFG.get("o2_ref") != "own":
            if not hasattr(Oracle, "_cal"):
                z = np.load(CFG.get("o2_cal", "scratchpad/tt3/results/o2_cal_A_diag.npz"))
                Oracle._cal = {"n1": z["n1"], "n2": z["n2"], "qbar1": z["qbar1"], "qbar2": z["qbar2"], "fbar1": z["fbar1"], "fbar2": z["fbar2"],
                               "g1": np.diag(z["G1"]).copy() * float(CFG.get("o2_gscale", 1.0)), "g2": np.diag(z["G2"]).copy() * float(CFG.get("o2_gscale", 1.0))}
            self.cal = Oracle._cal
        if self.modes & {"rec", "o2"}:
            p = sim.params
            self.side_bh = False
            # ONE continuous fit for both sides (the arm muscles cross no trunk joint, so the trunk's turn does not enter), warm-started from the measured reset
            # posture (the first targets are the measured contractions) and tracked tick by tick: a cold start at the side change fell into a wrong basin
            self.fit = ArmFit(sim, (p.get("trunk_fe", 0.0), p.get("trunk_lb", 0.0), p.get("trunk_ar", 0.0)))
        # the puppet (o4)
        self.plan = None
        if self.modes & {"o4", "o5"}:
            self.load_plan()
        self.restore_geoms()
        if self.plan is not None and "o4" in self.modes:
            self.apply_geoms()
        self.robot.__dict__.pop("_advance", None)             # a stale oracle of a crashed episode must not be chained
        self.orig_advance = self.robot._advance
        self.robot._advance = self.advance
        self.pel_v_prev = None
        self.o1_poly = None

    # ---- pass-1 record ---------------------------------------------------------------
    def load_pass1(self):
        f = os.path.join(PASS1, f"{self.seed}.npz")
        z = np.load(f)
        L, X, k = z["L"], z["X"], int(z["contact"])
        if k < 0:   # a miss: the ball's closest approach to the pad
            dist = np.linalg.norm(L[:, 1:4] - L[:, 7:10], axis=1)
            k = int(np.argmin(dist))
        self.tc = float(L[k, 0])
        self.qc = np.array(X[k, 10:12], float)
        self.hit1 = int(z["contact"]) >= 0

    def load_plan(self):
        if not hasattr(Oracle, "_plans"):
            Oracle._plans = json.load(open(PLAN))
        p = Oracle._plans.get(str(self.seed))
        if p is None:
            return
        self.plan = {k: (np.array(v, float) if isinstance(v, list) else v) for k, v in p.items()}

    # ---- geometry switches (o4) --------------------------------------------------------
    def restore_geoms(self):
        m = self.m
        key = id(m)
        names = O4_GEOMS
        if key not in _PRISTINE:
            _PRISTINE[key] = {n: (int(m.geom_contype[m.geom(n).id]), int(m.geom_conaffinity[m.geom(n).id])) for n in names}
        for n, (ct, ca) in _PRISTINE[key].items():
            g = m.geom(n).id
            m.geom_contype[g], m.geom_conaffinity[g] = ct, ca

    def apply_geoms(self):
        """the ball meets only the pad disc, the table halves, the net and the floor (a hand left where the champion's arm is must not catch the rebound);
        the puppeted paddle meets only the ball (contype/conaffinity bit 2; the table, net and floor carry bits 1 and 2)"""
        m = self.m
        g = m.geom("pad").id
        m.geom_contype[g] = m.geom_conaffinity[g] = 2
        g = m.geom("handle").id
        m.geom_contype[g] = m.geom_conaffinity[g] = 0
        g = m.geom("pingpong").id
        m.geom_contype[g] = m.geom_conaffinity[g] = 2
        for n in ("coll_own_half", "coll_opponent_half", "coll_net", "ground"):
            g = m.geom(n).id
            m.geom_contype[g] = m.geom_conaffinity[g] = 3

    # ---- per tick (after the controller's reply, before the env steps) ------------------
    def pre_step(self, act):
        sim = self.sim
        t = float(sim.d.time)
        i = self.tick_i
        self.tick_i += 1
        row = {"t": t}
        if self.log and "o2" in self.modes:
            self.log[-1]["tau"] = self.tau_tick.copy()      # the peak torque estimate of the tick that has just run
        self.tau_tick = np.zeros(7)
        if self.fit is not None:
            self.arm_tick(t, row)
        if "o5" in self.modes:
            self.padservo_tick(t, row)
            if CFG.get("o5_mus_off") and self.q_ref is not None:
                # the ideal servo is the arm's ONLY actuator while it runs: the 32 arm muscles' activations are set to zero (hand and trunk muscles stay the champion's)
                if not hasattr(self, "arm_mus"):
                    self.arm_mus = [i for i, mu in enumerate(sim.muscles) if mu.name in ARM_MUSCLES]
                act[self.arm_mus] = 0.0
        if "o1" in self.modes:
            self.pelvis_tick(t, row)
        self.log.append(row)

    def arm_tick(self, t, row):
        sim = self.sim
        side = getattr(sim, "tt_side", 0)
        fit = self.fit
        q = np.array([self.d.qpos[a] for a in self.arm_q])
        first = fit.x is None
        qfit, s, res = fit.solve(sim.targets, x0=q if first else None, iters=12 if first else 5)
        qd = np.array([self.d.qvel[a] for a in self.arm_d])
        row.update(qfit=qfit, s=s, res=res, q=q, qd=qd, side=side)
        if "o2" in self.modes and t + 1e-9 >= float(CFG.get("o2_tact", 0.25)):
            i = max(int(round(t / self.dt)), 0)
            if CFG.get("o2_ref") != "own":
                i = min(i, self.cal["n1"].shape[0] - 1)
            sd = 2 if side == 2 else 1
            g = self.cal[f"g{sd}"] if CFG.get("o2_ref") != "own" else None
            if CFG.get("o2_ref") == "own":  # this serve's OWN pass-1 reached trajectory (optionally smoothed: cfg o2_smooth = half window in ticks): the machinery's sanity check / a ringing-free arm
                if self.q_own is None:
                    z = np.load(os.path.join(CFG.get("o2_own_dir", "out/tt3/orc_rec"), f"{self.seed}.npz"))
                    Q = z["q"]
                    w = int(CFG.get("o2_smooth", 0))
                    if w > 0:
                        K = np.ones(2 * w + 1) / (2 * w + 1)
                        Qp = np.vstack([np.repeat(Q[:1], w, axis=0), Q, np.repeat(Q[-1:], w, axis=0)])
                        Q = np.stack([np.convolve(Qp[:, j], K, mode="valid") for j in range(7)], axis=1)
                    self.q_own = Q
                new = self.q_own[min(i + 1, len(self.q_own) - 1)].copy()
            elif CFG.get("o2_abs"):           # the LITERAL oracle: the reached posture = the asked posture (q_fit itself)
                new = qfit.copy()
            elif CFG.get("o2_gunit"):       # the asked deviation from the champion's mean is executed 1:1
                new = self.cal[f"qbar{sd}"][i] + (qfit - self.cal[f"fbar{sd}"][i])
            else:
                new = self.cal[f"qbar{sd}"][i] + g * (qfit - self.cal[f"fbar{sd}"][i])
            self.q_prev = self.q_ref.copy() if self.q_ref is not None else q.copy()
            step = np.clip(new - self.q_prev, -0.12 * self.dt / 0.01, 0.12 * self.dt / 0.01)   # never move the reference faster than 12 rad/s (the fit can hop between redundant postures)
            new = self.q_prev + step
            self.qd_ref = (new - self.q_prev) / self.dt
            self.q_ref = new
            row["qref"] = new.copy()
            # computed-torque PD: the torque is the arm joints' 7 x 7 block of the mass matrix (live, once per tick) times the desired acceleration w^2 e + 2 zeta w de; a diagonal-gain
            # PD went unstable (torques of 1e6 N m: near-parallel wrist axes leave modes with only the joints' 1e-4 armature)
            M = np.zeros((self.m.nv, self.m.nv))
            self.mj.mj_fullM(self.m, M, self.d.qM)
            self.Maa = M[np.ix_(self.arm_d, self.arm_d)].copy()
            self.w = float(CFG.get("o2_omega", 150.0))
            self.zeta = float(CFG.get("o2_zeta", 1.0))

    def padservo_tick(self, t, row):
        """o5 IDEAL ARM FOLLOWING THE PADDLE-POSE GOAL: from t_act (cfg o5_tact, 0.25 s) to the planned contact the 7 arm joints are driven (computed-torque PD, the same as o2) toward
        q_ref = q + alpha dq, dq the damped-least-squares joint change (the hand's live Jacobians crossed with the pad's offset from the palm, as the controller's own servo) that takes the pad
        centre to the plan's pad line P + v (t - t_hit) and its normal to the plan's; alpha = 1 - exp(-dt / tau) (cfg o5_tau, 0.05 s). The champion's own controller keeps running (its servo aims at
        ITS aim; the torque overpowers it); the paddle is held by the champion's grip; nothing is puppeted."""
        sim, p = self.sim, self.plan
        if p is None or t + 1e-9 < float(CFG.get("o5_tact", 0.25)) or t > p["t_hit"] + float(CFG.get("o5_hold", 0.0)):
            self.q_ref = None
            return
        m, d = sim.m, sim.d
        pad_g = m.geom("pad").id
        c = np.array(d.geom_xpos[pad_g])
        n = np.array(d.geom_xmat[pad_g]).reshape(3, 3)[:, 2]
        n = n * (1.0 if n[0] >= 0 else -1.0)
        n_goal = -np.array(p["n_out"])
        n_goal = n_goal / np.linalg.norm(n_goal)
        G = np.array(p["P"]) + np.array(p["v"]) * (t + self.dt - p["t_hit"])
        Jv_Jw = sim.task.hand_jacobian(sim)
        JV = np.array(Jv_Jw[:24]).reshape(3, 8)[:, :7]
        JW = np.array(Jv_Jw[24:]).reshape(3, 8)[:, :7]
        palm = np.array(d.site_xpos[m.site("S_grasp").id])
        r = c - palm
        Jp = JV + np.cross(JW.T, r).T
        Pn = np.eye(3) - np.outer(n, n)
        wr = float(CFG.get("o5_wrot", 0.25))
        A = np.vstack([Jp, wr * (Pn @ JW)])
        e_p = G - c
        e_r = np.cross(n, n_goal)
        b = np.r_[e_p, wr * (Pn @ e_r)]
        lam = float(CFG.get("o5_lam", 1e-3))
        dq = A.T @ np.linalg.solve(A @ A.T + lam * np.eye(6), b)
        if CFG.get("o5_togo"):
            # decelerating approach: close the fraction 2 dt / T_go of the remaining error per tick (T_go = time to the planned contact): e ~ T_go^2, so the pad arrives AT REST
            alpha = min(1.0, 2.0 * self.dt / max(p["t_hit"] - t, self.dt))
        else:
            alpha = 1.0 - np.exp(-self.dt / float(CFG.get("o5_tau", 0.05)))
        q = np.array([self.d.qpos[a] for a in self.arm_q])
        step = np.clip(alpha * dq, -0.15, 0.15)
        self.q_prev = q.copy()
        self.q_ref = q + step
        self.qd_ref = step / self.dt
        M = np.zeros((self.m.nv, self.m.nv))
        self.mj.mj_fullM(self.m, M, self.d.qM)
        self.Maa = M[np.ix_(self.arm_d, self.arm_d)].copy()
        self.w = np.array([float(CFG.get("o2_omega", 150.0))] * 4 + [float(CFG.get("o2_omega_distal", CFG.get("o2_omega", 150.0)))] * 3)
        self.zeta = float(CFG.get("o2_zeta", 1.0))
        row.update(pad_err=np.r_[e_p, np.degrees(np.linalg.norm(e_r))], q=q, qref=self.q_ref.copy())

    def pelvis_tick(self, t, row):
        """o1: until t_a = tc - lead the pelvis is the champion's own (its commands untouched, so the run is pass 1's); from t_a the two slides follow a quintic from
        the measured state (position, velocity, acceleration) to the pass-1 contact position at rest, arriving at ts = tc - margin and held. The command adds the
        force the reference needs, (m a + c v) / kp, as the controller's own set_pelvis does."""
        sim = self.sim
        margin = float(CFG.get("o1_margin", 0.15))
        lead = float(CFG.get("o1_lead", 0.35))
        q = np.array([self.d.qpos[a] for a in self.pel_q])
        v = np.array([self.d.qvel[a] for a in self.pel_d])
        acc = (v - self.pel_v_prev) / self.dt if self.pel_v_prev is not None else np.zeros(2)
        self.pel_v_prev = v.copy()
        t_a = self.tc - lead
        if self.o1_poly is None and float(CFG.get("o1_vmax", 0.0)) > 0.0:
            # adaptive start: as late as the slides can still arrive by tc - margin: the blend starts when the time left covers the remaining distance at o1_vmax (min-jerk peak 1.875 d / T)
            dist = float(np.max(np.abs(self.qc - q)))
            need = max(float(CFG.get("o1_tmin", 0.2)), 1.875 * dist / float(CFG["o1_vmax"]))
            t_a = self.tc - margin - need
        if self.o1_poly is None and t + 1e-9 < t_a:
            row.update(pel_q=q, pel_v=v)
            return
        if self.o1_poly is None:
            T = max(self.tc - margin - t, 0.05)
            # quintic q(tau) = q + v tau + acc tau^2/2 + c3 tau^3 + c4 tau^4 + c5 tau^5 with q(T) = qT, q'(T) = vend, q''(T) = 0; vend = 0 (settled) or, with cfg o1_vend_file
            # (o1c), the champion's side-mean terminal velocity, carried at constant velocity to the contact: qT = qc - vend * margin
            vend = np.zeros(2)
            if CFG.get("o1_vend_file"):
                if not hasattr(Oracle, "_vend"):
                    Oracle._vend = json.load(open(CFG["o1_vend_file"]))
                vend = np.array(Oracle._vend[str(2 if getattr(sim, "tt_side", 0) == 2 else 1)], float)
            qT = self.qc - vend * margin
            A = np.array([[T ** 3, T ** 4, T ** 5], [3 * T ** 2, 4 * T ** 3, 5 * T ** 4], [6 * T, 12 * T ** 2, 20 * T ** 3]])
            rhs = np.stack([qT - q - v * T - 0.5 * acc * T * T, vend - (v + acc * T), -acc])   # 3 x 2
            C = np.linalg.solve(A, rhs)
            self.o1_poly = (t, T, q.copy(), v.copy(), acc.copy(), C, qT, vend)
        t0, T, q0, v0, a0, C, qT, vend = self.o1_poly
        tau = min(max(t + self.dt - t0, 0.0), T)
        r = q0 + v0 * tau + 0.5 * a0 * tau ** 2 + C[0] * tau ** 3 + C[1] * tau ** 4 + C[2] * tau ** 5
        rv = v0 + a0 * tau + 3 * C[0] * tau ** 2 + 4 * C[1] * tau ** 3 + 5 * C[2] * tau ** 4
        ra = a0 + 6 * C[0] * tau + 12 * C[1] * tau ** 2 + 20 * C[2] * tau ** 3
        if t + self.dt - t0 >= T:
            r, rv, ra = qT + vend * (t + self.dt - t0 - T), vend.copy(), np.zeros(2)
        pel_m = float(sim.params.get("pel_m", 139.0))
        fb = float(sim.params.get("pel_fb", 0.5))
        u = r + fb * (r - q) + (pel_m * ra + 1000.0 * rv) / 3500.0
        ax = min(max((u[0] + 0.475) / 0.525, -1.0), 1.0)
        ay = min(max(u[1], -1.0), 1.0)
        sim.motor_cmd["pelvis_x"] = float(ax)
        sim.motor_cmd["pelvis_y"] = float(ay)
        row.update(pel_ref=r, pel_v=v, pel_q=q)

    # ---- physics substeps (Robot._advance replacement) ---------------------------------
    def advance(self, model, data, n_frames=1, render=None):
        mj = self.mj
        h = float(model.opt.timestep)
        o2 = self.q_ref is not None and bool(self.modes & {"o2", "o5"})
        mech = CFG.get("o2_mech", "pd")
        for k in range(n_frames):
            if self.plan is not None and "o4" in self.modes:
                self.puppet(model, data)
            if o2 and mech == "pd":
                # computed-torque PD on the 7 arm joints: torque = M_aa (w^2 e + 2 zeta w de) with the joints' live 7 x 7 mass block; the applied torque is recorded
                q = data.qpos[self.arm_q]
                qd = data.qvel[self.arm_d]
                tau = self.Maa @ (self.w ** 2 * (self.q_ref - q) + 2 * self.zeta * self.w * (self.qd_ref - qd))
                if CFG.get("o5_ff"):   # inverse-dynamics feed-forward: gravity + Coriolis, minus what the (decaying) muscles still supply
                    tau = tau + data.qfrc_bias[self.arm_d] - data.qfrc_actuator[self.arm_d]
                tau = np.clip(tau, -TAU_MAX, TAU_MAX) if np.all(np.isfinite(tau)) else np.zeros(7)
                data.qfrc_applied[self.arm_d] = tau
                self.tau_tick = np.maximum(self.tau_tick, np.abs(tau))
                self.tau_peak = np.maximum(self.tau_peak, np.abs(tau))
                self.tau_sq += tau ** 2
                self.tau_n += 1
            mj.mj_step(model, data)
            if o2 and mech == "kin":
                # the ideal servo (infinite gain, no lag): after every substep the 7 arm joints ARE the reference (position on the straight line from last tick's reference
                # to this tick's, velocity its slope); the torque this takes is estimated as M_aa (a_ref - the free acceleration qacc of the substep just run)
                frac = (k + 1) / n_frames
                qr = self.q_prev + (self.q_ref - self.q_prev) * frac
                qdr = self.qd_ref
                a_free = data.qacc[self.arm_d]
                tau = self.Maa @ ((qdr - (self.qd_last if k > 0 else self.qd_prev_tick)) / h - a_free)
                if np.all(np.isfinite(tau)):
                    self.tau_tick = np.maximum(self.tau_tick, np.abs(tau))
                    self.tau_peak = np.maximum(self.tau_peak, np.abs(tau))
                    self.tau_sq += tau ** 2
                    self.tau_n += 1
                data.qpos[self.arm_q] = qr
                data.qvel[self.arm_d] = qdr
                self.qd_last = qdr.copy()
        if o2:
            self.qd_prev_tick = self.qd_ref.copy()
        if self.q_ref is None and self.d.qfrc_applied[self.arm_d[0]] != 0.0:
            self.d.qfrc_applied[self.arm_d] = 0.0

    def puppet(self, model, data):
        p = self.plan
        t = float(data.time)
        if t < p["t_on"] or t > p["t_off"]:
            return
        n_out = p["n_out"]                                    # unit normal from the pad toward the incoming ball
        if "xax" not in p:
            xc = data.xmat[self.pad_body].reshape(3, 3)[:, 0].copy()
            xc = xc - (xc @ n_out) * n_out
            if np.linalg.norm(xc) < 1e-6:
                xc = np.array([0.0, 1.0, 0.0]) - n_out[1] * n_out
            xc = xc / np.linalg.norm(xc)
            p["xax"] = xc
            zax = -n_out                                      # the paddle body's z axis is the pad normal (either sign)
            yax = np.cross(zax, xc)
            R = np.stack([xc, yax, zax], axis=1)
            quat = np.zeros(4)
            self.mj.mju_mat2Quat(quat, R.flatten())
            p["quat"] = quat
        P = p["P"] + p["v"] * (t - p["t_hit"])                # the pad centre now
        pos = P + 0.07 * p["xax"]                             # body origin = pad centre + 0.07 along the paddle's x axis
        data.qpos[self.pad_q:self.pad_q + 3] = pos
        data.qpos[self.pad_q + 3:self.pad_q + 7] = p["quat"]
        data.qvel[self.pad_d:self.pad_d + 3] = p["v"]
        data.qvel[self.pad_d + 3:self.pad_d + 6] = 0.0

    # ---- end of the episode --------------------------------------------------------------
    def finish(self, sim, out):
        self.robot.__dict__.pop("_advance", None)
        self.d.qfrc_applied[:] = 0.0
        self.restore_geoms()
        ex = {"orc": "+".join(sorted(self.modes))}
        if "o1" in self.modes:
            ex.update(o1_tc=round(self.tc, 3), o1_qc=[round(float(x), 4) for x in self.qc])
        if self.modes & {"o2", "o5"}:
            ex.update(o2_tau_peak=[round(float(x), 2) for x in self.tau_peak],
                      o2_tau_rms=[round(float(x), 2) for x in np.sqrt(self.tau_sq / max(self.tau_n, 1))])
        if self.plan is not None:
            ex.update(o4_t_hit=round(float(self.plan["t_hit"]), 3))
        if "o5" in self.modes:
            pe = [r["pad_err"] for r in self.log if "pad_err" in r]
            if pe:
                ex.update(o5_pad_err_last=[round(float(x), 4) for x in pe[-1]])
        if self.fit is not None:
            R = [r["res"] for r in self.log if "res" in r]
            ex.update(fit_res_median=round(float(np.median(R)), 5) if R else None)
        if LOGDIR:
            os.makedirs(LOGDIR, exist_ok=True)
            keys = ("t", "qfit", "s", "res", "q", "qd", "qref", "pel_ref", "pel_v", "pel_q", "side", "tau", "pad_err")
            arrs = {}
            for k in keys:
                vals = [r.get(k) for r in self.log]
                if any(v is not None for v in vals):
                    dim = next(np.size(v) for v in vals if v is not None)
                    arrs[k] = np.array([np.full(dim, np.nan) if v is None else np.atleast_1d(v) for v in vals], float)
            np.savez_compressed(os.path.join(LOGDIR, f"{self.seed}.npz"), **arrs)
        out.update(ex)
        return out


class MyoTTOracleTask(MyoTTTask):
    """MyoTTTask, with the oracle installed when MYO_TT_ORACLE names a mode (else the official task, untouched)."""

    def extra_sensors(self, sim):
        if MODES and not hasattr(sim, "_orc"):
            sim._orc = Oracle(sim)
            orig = sim.action_from

            def action_from(act, _o=sim._orc, _orig=orig):
                _o.pre_step(act)
                return _orig(act)

            sim.action_from = action_from
        return super().extra_sensors(sim)

    def metrics(self, sim, log):
        out = super().metrics(sim, log)
        if MODES and hasattr(sim, "_orc"):
            sim._orc.finish(sim, out)
        return out


TASK = MyoTTOracleTask
