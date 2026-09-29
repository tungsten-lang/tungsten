"""MyoChallenge soccer body with a guard against MuJoCo's tendon-wrap NaN (labelled diagnostic variant "nanguard").

WHY. A held one-leg stance was found to end, about once in 5000 start-seconds, in "Nan, Inf or huge value in QACC at DOF 6. The simulation
is unstable": MuJoCo resets the data and the kicker collapses. Root cause (scratchpad/blowup/LOG.md, playground/repros/mujoco_wrap_nan.md):
MuJoCo's length_circle (3.2.7 ... 3.14.0) computes acos(dot(p0n, p1n)) of two normalised tangent points of a cylinder/sphere tendon wrap;
when the tendon line only grazes the wrapping geom (relative margin < ~6e-8) the points are about 2e-8 rad apart, the dot product rounds
above 1.0 (about one case in ten), acos returns NaN, mju_wrap's `wlen < 0` test does not see the NaN, and the tendon length, its moment
arms and the muscle force become NaN. In the one-leg holds it is the right rectus femoris (recfem_r_tendon, cylinder KnExt_at_fem_r_wrap)
of the parked swing leg, which hovers at that tangent (the ramp entries about 3x more than the lift entry); trunk tendons can meet it
too (IL_L1_r_tendon on back_cylinder_s, start 96029 at 2.12 s). It is a numerical accident, not a physical failure of the stance.

WHAT THIS TASK CHANGES (and nothing else: contacts, muscles, reset, scoring, sensors and the soccer metrics are MyoSoccerTask's).
The stepped MjData (MyoSuite's Robot owns its own MjData; env.mj_data is only a sensor-synced mirror) advances through
`NanGuard.advance` instead of Robot._advance: each substep snapshots the integration state (mj_getState, read-only), calls mj_step
exactly as MyoSuite does, and only if MuJoCo reset the data (time went backwards) looks at what failed. If a tendon length is NaN at
the snapshot (the wrap bug) the substep is redone from the snapshot after a deterministic nudge of the hinge/slide joint angles
(1e-10 rad, growing x10 every 3 tries up to 1e-6 rad: far below anything the controller or the physics can resolve) which moves
the state out of the arithmetic sliver. Any other instability (no NaN tendon) is replayed exactly as MuJoCo would have produced it.
The same NaN reaches the controller through the other MjData: when the sliver state is the one at a control-step boundary, MyoSuite's
sensor-synced mirror (env.mj_data, the data MyoSim reads muscle lengths from) evaluates it first, the controller receives a NaN muscle
length, returns a NaN activation, and MuJoCo answers "CTRL at ACTUATOR n" by zeroing ALL controls. `on_step` therefore checks the mirror
after every control step and nudges the stepped data and the mirror the same way before the controller reads them.
While no NaN tendon occurs a rollout is BIT-IDENTICAL to the official environment's (the guard and the telemetry only read state), so every
start that never hits the sliver scores exactly what MyoSoccerTask scores (checked on 119 of 119 event-free 20 s starts and every re-run).

Mode by env var MYO_SOCCER_NANGUARD: 1 (default) nudge and continue; 0 count only (the official behaviour: the reset ends the hold).

Extra metrics: nan_events (states whose tendon length was NaN), nan_nudged (recovered), nan_other (resets without a NaN tendon), nan_mirror (of the
events, those first seen by the observation mirror at a control-step boundary), nan_first_t, nan_tendons (comma-separated names);
wrap_{r,l}_near3/near4/flips/minpos (control-step graze statistics of the two rectus femoris wraps) and, per substep, wrap_{r,l}_hist /
_substeps / _visits / _visit_omd, nan_omd, nan_expected (the sliver states met and P(NaN)); hold20 (20 s trials: 1 when the kicker is
standing since the start and has been on one leg for the last 15 s of the episode).
"""

import os
import sys
from decimal import Decimal, getcontext

import mujoco
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from tasks.myo_soccer import MyoSoccerTask  # noqa: E402

SPEC = int(mujoco.mjtState.mjSTATE_INTEGRATION)
NUDGES = [1e-10, 1e-10, 1e-10, 1e-9, 1e-9, 1e-9, 1e-8, 1e-8, 1e-8, 1e-7, 1e-7, 1e-7, 1e-6, 1e-6, 1e-6]


class NanGuard:
    """Counts and (optionally) recovers the tendon-wrap NaN of the stepped MjData."""

    def __init__(self, m, recover=True):
        self.m = m
        self.recover = recover
        self.spec_size = mujoco.mj_stateSize(m, SPEC)
        self.snap = np.empty(self.spec_size)
        self.hinge_slide = np.array([m.jnt_qposadr[j] for j in range(m.njnt)
                                     if m.jnt_type[j] in (mujoco.mjtJoint.mjJNT_HINGE, mujoco.mjtJoint.mjJNT_SLIDE)])
        self.events = 0
        self.nudged = 0
        self.other = 0
        self.tries = 0
        self.mirror_events = 0
        self.first_t = None
        self.tendons = []
        self.watch = None  # WrapWatch, set by the task

    def advance(self, robot, model, data, n_frames=1, render=None):
        watch = self.watch
        for _ in range(n_frames):
            mujoco.mj_getState(model, data, self.snap, SPEC)
            t0 = float(data.time)
            mujoco.mj_step(model, data)
            if float(data.time) < t0:  # mj_checkAcc reset the data: a bad qacc in this substep
                self.after_reset(model, data, t0)
            elif watch is not None and t0 >= 3.0:
                watch.sub(data)  # graze margins of the state this substep evaluated (read-only telemetry)

    def note(self, model, bad, t):
        if self.first_t is None:
            self.first_t = t
        for k in bad:
            name = mujoco.mj_id2name(model, mujoco.mjtObj.mjOBJ_TENDON, int(k))
            if name not in self.tendons:
                self.tendons.append(name)

    def check_mirror(self, sim):
        """The sensor-synced mirror (sim.d) evaluated a sliver state: repair before the controller reads its muscle lengths."""
        d, rd, m = sim.d, sim.u.robot.mj_data, sim.m
        if np.isfinite(d.ten_length).all():
            return
        t = float(d.time)
        self.mirror_events += 1
        self.events += 1
        self.note(m, np.flatnonzero(~np.isfinite(d.ten_length)), t)
        if self.watch is not None:
            self.watch.event(d)
        if not self.recover:
            return
        base = rd.qpos.copy()
        rng = np.random.default_rng(int(round(t * 1000)) + 7)
        for amp in NUDGES:
            self.tries += 1
            rd.qpos[:] = base
            rd.qpos[self.hinge_slide] += amp * rng.standard_normal(self.hinge_slide.size)
            d.qpos[:] = rd.qpos
            mujoco.mj_forward(m, d)
            if np.isfinite(d.ten_length).all() and np.isfinite(d.actuator_velocity).all():
                self.nudged += 1
                return
        rd.qpos[:] = base
        d.qpos[:] = base
        mujoco.mj_forward(m, d)

    def refresh_obs(self, sim):
        """the env's obs_dict was computed from the NaN mirror inside env.step: recompute it from the repaired one"""
        try:
            u = sim.u
            u.obs_dict = u.get_obs_dict(u.obsd_mj_model, u.obsd_mj_data)
        except Exception:
            pass

    def after_reset(self, model, data, t0):
        mujoco.mj_setState(model, data, self.snap, SPEC)
        mujoco.mj_fwdPosition(model, data)
        bad = np.flatnonzero(~np.isfinite(data.ten_length))
        if bad.size == 0:
            # not the wrap bug: a genuine instability, replay the step as MuJoCo did (deterministic) and let it stand
            self.other += 1
            mujoco.mj_setState(model, data, self.snap, SPEC)
            mujoco.mj_step(model, data)
            return
        self.events += 1
        self.note(model, bad, t0)
        if self.watch is not None:
            self.watch.event(data)  # data holds the snapshot state after mj_fwdPosition
        if not self.recover:
            mujoco.mj_setState(model, data, self.snap, SPEC)
            mujoco.mj_step(model, data)  # the official behaviour: MuJoCo resets again
            return
        rng = np.random.default_rng(int(round(t0 * 1000)))
        for amp in NUDGES:
            self.tries += 1
            mujoco.mj_setState(model, data, self.snap, SPEC)
            data.qpos[self.hinge_slide] += amp * rng.standard_normal(self.hinge_slide.size)
            mujoco.mj_step(model, data)
            if float(data.time) >= t0:
                self.nudged += 1
                return
        # never recovered: leave MuJoCo's reset in place (the rollout ends as the official one would)


EDGES = [0.0, 1e-8, 6e-8, 1e-7, 1e-6, 1e-5, 1e-4, 1e-3, 1e-2, 1e9]   # |margin| bins of the substep histogram
# P(NaN | exact 1 - dot of the tangent points), measured on the real library (scratchpad/blowup/nan_band_scan.py, 40001 mj_fwdPosition calls)
P_NAN = [(1e-17, 0.295), (3e-17, 0.202), (6e-17, 0.135), (8e-17, 0.071), (1e-16, 0.047), (1.2e-16, 0.045), (1.5e-16, 0.022), (2.5e-16, 0.004)]


def p_nan(omd):
    for hi, p in P_NAN:
        if omd < hi:
            return p
    return 0.0


def exact_omd(end, sd, r):
    """1 - dot of the two normalised tangent points of the near-coincident pair, in 60-digit arithmetic (the two tangent lines of wrap_circle)"""
    getcontext().prec = 60
    e = [Decimal(float(x)) for x in end]
    rr = Decimal(r)
    sq0, sq1, sqr = e[0] * e[0] + e[1] * e[1], e[2] * e[2] + e[3] * e[3], rr * rr
    if sq0 <= sqr or sq1 <= sqr:
        return None
    a0, a1 = (sq0 - sqr).sqrt(), (sq1 - sqr).sqrt()
    best = None
    for sgn in (1, -1):
        s00 = (e[0] * sqr + sgn * rr * e[1] * a0) / sq0
        s01 = (e[1] * sqr - sgn * rr * e[0] * a0) / sq0
        s10 = (e[2] * sqr - sgn * rr * e[3] * a1) / sq1
        s11 = (e[3] * sqr + sgn * rr * e[2] * a1) / sq1
        n0, n1 = (s00 * s00 + s01 * s01).sqrt(), (s10 * s10 + s11 * s11).sqrt()
        omd = 1 - (s00 * s10 + s01 * s11) / (n0 * n1)
        best = omd if best is None or omd < best else best
    return float(best)


class WrapWatch:
    """Graze margins of the two rectus femoris cylinder wraps (the tendons that met the NaN): margin = (r^2 - |tmp|^2) / r^2 in the
    wrap's 2D frame (tmp = the tendon line's nearest point to the cylinder axis), > 0 when the line cuts the cylinder. Read-only
    telemetry from the stepped MjData's last forward pass. step(): per control step (t >= 3 s), per tendon the steps with |margin| < 1e-3
    and < 1e-4, sign changes (the leg straddling the tangent), the smallest positive margin. sub(): per substep a histogram of the
    margin and, for the states in the NaN sliver (0 < margin < 1e-7), the exact 1 - dot; event(): the same for a state that was NaN.
    expected = sum of P(NaN | exact 1 - dot) over the sliver states that survived and the ones that were NaN."""

    NAMES = ("recfem_r_tendon", "recfem_l_tendon")

    def __init__(self, m):
        self.segs = []
        for nm in self.NAMES:
            t = mujoco.mj_name2id(m, mujoco.mjtObj.mjOBJ_TENDON, nm)
            adr = m.tendon_adr[t]
            for j in range(m.tendon_num[t] - 2):
                if int(m.wrap_type[adr + j + 1]) == int(mujoco.mjtWrap.mjWRAP_CYLINDER):
                    g = int(m.wrap_objid[adr + j + 1])
                    self.segs.append((nm, int(m.wrap_objid[adr + j]), g, int(m.wrap_objid[adr + j + 2]), float(m.geom_size[g][0])))
        self.acc = {s[0]: {"n": 0, "near3": 0, "near4": 0, "flips": 0, "minpos": 9.0, "last": None} for s in self.segs}
        self.side = {}
        for nm, s0, g, s1, r in self.segs:
            t = mujoco.mj_name2id(m, mujoco.mjtObj.mjOBJ_TENDON, nm)
            adr = m.tendon_adr[t]
            for j in range(m.tendon_num[t] - 2):
                if int(m.wrap_objid[adr + j]) == s0 and int(m.wrap_objid[adr + j + 1]) == g:
                    self.side[nm] = int(round(m.wrap_prm[adr + j + 1]))
        self.hist = {s[0]: [np.zeros(len(EDGES) - 1, dtype=np.int64), np.zeros(len(EDGES) - 1, dtype=np.int64), 0] for s in self.segs}  # positive, negative, substeps
        self.visits = {s[0]: [] for s in self.segs}   # exact 1 - dot of survived sliver states
        self.events_omd = []                          # exact 1 - dot of NaN states (nearest watched segment in the sliver)
        self.expected = 0.0

    def margin_end(self, d, seg):
        nm, s0, g, s1, r = seg
        xm = d.geom_xmat[g].reshape(3, 3)
        c = d.geom_xpos[g]
        p0 = xm.T @ (d.site_xpos[s0] - c)
        p1 = xm.T @ (d.site_xpos[s1] - c)
        dif = p1[:2] - p0[:2]
        dd = float(dif @ dif)
        if dd < 1e-15:
            return None, None, None
        a = min(max(-float(dif @ p0[:2]) / dd, 0.0), 1.0)
        tmp = a * dif + p0[:2]
        mg = (r * r - float(tmp @ tmp)) / (r * r)
        return mg, (p0[0], p0[1], p1[0], p1[1]), (xm, c)

    def omd_of(self, d, seg, end):
        """exact 1 - dot for the state whose kinematics d holds (sidesite direction is irrelevant to the near-coincident pair's angle)"""
        return exact_omd(end, None, seg[4])

    def sub(self, d):
        for seg in self.segs:
            mg, end, _ = self.margin_end(d, seg)
            if mg is None:
                continue
            nm = seg[0]
            h = self.hist[nm]
            h[2] += 1
            b = int(np.searchsorted(EDGES, abs(mg), side="right")) - 1
            b = min(max(b, 0), len(EDGES) - 2)
            h[0 if mg > 0 else 1][b] += 1
            if 0 < mg < 1e-7:
                omd = self.omd_of(d, seg, end)
                if omd is not None:
                    v = self.visits[nm]
                    if len(v) < 400:
                        v.append(omd)
                    self.expected += p_nan(omd)

    def event(self, d):
        """a NaN state: d holds its kinematics (position stage evaluated); log the exact 1 - dot of the watched segment that grazes"""
        best = None
        for seg in self.segs:
            mg, end, _ = self.margin_end(d, seg)
            if mg is None or not (0 < mg < 1e-6):
                continue
            omd = self.omd_of(d, seg, end)
            if omd is not None and (best is None or omd < best):
                best = omd
        if best is not None:
            self.events_omd.append(best)
            self.expected += p_nan(best)

    def step(self, d):
        for nm, s0, g, s1, r in self.segs:
            xm = d.geom_xmat[g].reshape(3, 3)
            c = d.geom_xpos[g]
            p0 = xm.T @ (d.site_xpos[s0] - c)
            p1 = xm.T @ (d.site_xpos[s1] - c)
            dif = p1[:2] - p0[:2]
            dd = float(dif @ dif)
            if dd < 1e-15:
                continue
            a = min(max(-float(dif @ p0[:2]) / dd, 0.0), 1.0)
            tmp = a * dif + p0[:2]
            mg = (r * r - float(tmp @ tmp)) / (r * r)
            acc = self.acc[nm]
            acc["n"] += 1
            if abs(mg) < 1e-3:
                acc["near3"] += 1
            if abs(mg) < 1e-4:
                acc["near4"] += 1
            if mg > 0:
                acc["minpos"] = min(acc["minpos"], mg)
            pos = mg > 0
            if acc["last"] is not None and acc["last"] != pos:
                acc["flips"] += 1
            acc["last"] = pos


class NanGuardSoccerTask(MyoSoccerTask):
    def episode(self, sim):
        first = getattr(self, "_sim", None) is not sim
        super().episode(sim)
        if first:
            robot = sim.u.robot
            self.guard = NanGuard(robot.mj_model, recover=os.environ.get("MYO_SOCCER_NANGUARD", "1") != "0")
            guard = self.guard
            self.watch = WrapWatch(robot.mj_model)
            guard.watch = self.watch
            robot._advance = lambda model, data, n_frames=1, render=None: guard.advance(robot, model, data, n_frames, render)

    def on_step(self, sim, obs, reward, info):
        self.episode(sim)
        n = self.guard.mirror_events
        self.guard.check_mirror(sim)
        if self.guard.mirror_events > n and self.guard.recover:
            self.guard.refresh_obs(sim)
        super().on_step(sim, obs, reward, info)
        if float(sim.d.time) >= 3.0:
            self.watch.step(sim.u.robot.mj_data)

    def metrics(self, sim, log):
        out = super().metrics(sim, log)
        g = getattr(self, "guard", None)
        out["nan_events"] = float(g.events) if g else 0.0
        out["nan_nudged"] = float(g.nudged) if g else 0.0
        out["nan_other"] = float(g.other) if g else 0.0
        out["nan_mirror"] = float(g.mirror_events) if g else 0.0
        w = getattr(self, "watch", None)
        if w:
            for nm, tag in (("recfem_r_tendon", "r"), ("recfem_l_tendon", "l")):
                a = w.acc.get(nm)
                if a and a["n"]:
                    out[f"wrap_{tag}_near3"] = round(a["near3"] / a["n"], 5)   # fraction of control steps within 1e-3 of the tangent
                    out[f"wrap_{tag}_near4"] = round(a["near4"] / a["n"], 5)   # ... within 1e-4
                    out[f"wrap_{tag}_flips"] = float(a["flips"])                # times the line crossed the tangent
                    out[f"wrap_{tag}_minpos"] = round(a["minpos"], 12) if a["minpos"] < 9 else None
            for nm, tag in (("recfem_r_tendon", "r"), ("recfem_l_tendon", "l")):
                h = w.hist.get(nm)
                if h and h[2]:
                    out[f"wrap_{tag}_hist"] = ",".join(str(int(x)) for x in h[0]) + "|" + ",".join(str(int(x)) for x in h[1])  # substeps per |margin| bin (positive|negative), EDGES
                    out[f"wrap_{tag}_substeps"] = float(h[2])
                    out[f"wrap_{tag}_visits"] = float(len(w.visits[nm]))                       # survived sliver states (0 < margin < 1e-7)
                    out[f"wrap_{tag}_visit_omd"] = ";".join(f"{x:.3e}" for x in w.visits[nm][:60])
            out["nan_omd"] = ";".join(f"{x:.3e}" for x in w.events_omd)
            out["nan_expected"] = round(w.expected, 5)   # sum of P(NaN | exact 1 - dot) over the sliver states met, survived or not
        out["nan_first_t"] = round(g.first_t, 3) if g and g.first_t is not None else None
        out["nan_tendons"] = ",".join(g.tendons) if g else ""
        # 20 s trials: standing since the start and on one leg for the last 15 s of the episode
        out["hold20"] = 1.0 if (self.stand_run and self.run1 >= 15.0) else 0.0
        return out


TASK = NanGuardSoccerTask
