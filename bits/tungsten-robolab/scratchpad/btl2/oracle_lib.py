"""Muscle-level oracle for one stroke: record a controller run, replay its activations from a snapshot, and let a
search overwrite the activations of chosen muscles (the ceiling study of round 2; nothing here runs the controller
after the recording, so a program found here is ORACLE-class).

    rec = record(seed, params, ctl, t_snap, t_end)            # runs the controller once (Sim), keeps ctrl series + snapshot
    rp = Replay(rec)                                           # a worker's replayer (own MjModel/MjData)
    out = rp.run(program)                                      # program: dict muscle index -> per-tick activations (len n_ticks) or None

`record` returns a dict of numpy arrays and the snapshot as (qpos, qvel, act, ctrl, time, warmstart) so it pickles.
"""
import os
import sys

import mujoco
import numpy as np

sys.path.insert(0, "playground")
sys.path.insert(0, "playground/tasks")

SUBSTEPS = 5
DT = 0.001
POSTURE_JOINTS = ["shoulder_flex", "shoulder_abd", "shoulder_rot", "elbow", "wrist_flex", "wrist_dev", "finger_mcp", "finger_pip"]


def build_sim(seed, params, ctl):
    from bridge import Sim
    from dribble_btl import DribbleBtlTask
    t = DribbleBtlTask()
    t.body_kind = "v3"
    t.seed = seed
    return t, Sim(t, params=params, controller=ctl)


def snapshot(d):
    return (d.qpos.copy(), d.qvel.copy(), d.act.copy(), d.ctrl.copy(), float(d.time), d.qacc_warmstart.copy(), d.eq_active.copy())


def record(seed, params, ctl, t_snap, t_end, t_last=None):
    """Run the controller once. Keeps the activations of every tick, the controller's label and the ball state per tick,
    and MuJoCo snapshots (before the tick) for every tick from t_snap to t_last (default t_snap only)."""
    t, sim = build_sim(seed, params, ctl)
    m, d = sim.m, sim.d
    t.reset(m, d)
    mujoco.mj_forward(m, d)
    sim.start_controller()
    acts, labels, ball, ballv = [], [], [], []
    snaps = {}
    t_last = t_snap if t_last is None else t_last
    try:
        while d.time < t_end - 1e-9:
            if t_snap - 1e-9 <= d.time <= t_last + 1e-9:
                snaps[len(acts)] = snapshot(d)
            act, c = sim.tick()
            acts.append(act.copy())
            labels.append(sim.label)
            for _ in range(SUBSTEPS):
                t.before_step(m, d)
                mujoco.mj_step(m, d)
            ball.append(d.body("ball").xpos.copy())
            ballv.append(d.qvel[t.ball_dof:t.ball_dof + 3].copy())
    finally:
        sim.stop_controller()
    k0 = min(snaps) if snaps else None
    try:
        metrics = t.metrics(m, d, [])
        pass_log = metrics.get("pass_log", [])
        streak = metrics.get("btl_streak", 0)
    except Exception:
        pass_log, streak = [], 0
    return {"seed": seed, "pass_log": pass_log, "streak": streak, "acts": np.array(acts), "snaps": snaps, "snap": snaps[k0] if snaps else None, "k0": k0,
            "act_ids": np.array(sim.act_ids), "ball": np.array(ball), "ballv": np.array(ballv), "labels": labels,
            "names": [mu.name for mu in sim.muscles]}


class Replay:
    def __init__(self, rec, params=None):
        from bridge import Sim
        from dribble_btl import DribbleBtlTask
        self.t = DribbleBtlTask()
        self.t.body_kind = "v3"
        self.t.seed = rec["seed"]
        self.sim = Sim(self.t, params=params or {}, controller="/nonexistent")
        self.m, self.d = self.sim.m, self.sim.d
        self.rec = rec
        self.act_ids = rec["act_ids"]
        self.t.reset(self.m, self.d)   # sets ids used below (ball, hands); the state is overwritten by the snapshot
        mujoco.mj_forward(self.m, self.d)
        self.ball_id = self.m.body("ball").id
        self.ball_geom = self.m.geom("ball").id
        self.floor_geom = self.m.geom("floor").id
        self.hand_geoms = {}
        for s in "lr":
            for g in ("hand", "fingers1", "fingers2"):
                self.hand_geoms[self.m.geom(f"{s}_{g}").id] = s
        self.ball_dof = self.m.jnt_dofadr[self.m.joint("ball").id]
        self.w = 0.62 * 9.81
        self._f6 = np.zeros(6)
        self.palm_ids = [self.m.site(f"{sd}_palm").id for sd in "lr"]
        self.leg_ids = [[self.m.body(f"{sd}_{part}").id for part in ("thigh", "shin", "foot")] for sd in "lr"]

    def load(self, k=None):
        q, v, a, c, tm, ws, eq = self.rec["snap"] if k is None else self.rec["snaps"][k]
        d = self.d
        d.qpos[:] = q
        d.qvel[:] = v
        d.act[:] = a
        d.ctrl[:] = c
        d.time = tm
        d.qacc_warmstart[:] = ws
        d.eq_active[:] = eq
        mujoco.mj_forward(self.m, d)

    def pred_cross(self, k, height=0.62):
        """(x, y, t): where and when the ball's centre will rise through `height`, as the skill's receive_state predicts it
        from the sensor frame at tick k (the state before that tick's step)."""
        self.load(k)
        d, m = self.d, self.m
        g = 9.81
        for name, vals in self.t.extra_sensors(m, d):
            if name == "ball_rise":
                r = list(vals)
        # the bridge's sensors read body positions as the last mj_step left them (one step stale), not as mj_forward
        # recomputes them; the recording has exactly those (the ball's position after the previous tick)
        if k >= 1:
            ps = self.rec["ball"][k - 1]
            if r[5] > 0.0:   # rising: the sensor's state is the current one
                r[0], r[1], r[2] = float(ps[0]), float(ps[1]), float(ps[2])
        vz = r[5]
        if vz <= 0.5:
            return None
        disc = vz * vz - 2.0 * g * (height - r[2])
        s = vz / g
        if disc > 0.0:
            s = (vz - np.sqrt(disc)) / g
        return (r[0] + r[3] * s, r[1] + r[4] * s, r[6] + s)

    def posture(self, k, side, zj, stale=True):
        """The stroking arm's posture features at the trigger tick k, as the skill's pg_nz features read them: for each joint index in `zj`
        (POSTURE_JOINTS) the contraction difference c(pos) - c(neg) of the joint's muscle pair from the sensor frame. The bridge's frame
        reads the muscle lengths as the last mj_step left them (one physics step before the state mj_forward recomputes here), so with
        `stale` the values are moved back by one step of the contraction rate."""
        self.load(k)
        c, cd, _ = self.sim.contraction()
        if stale:
            c = c - cd * DT
        names = self.rec["names"]
        out = []
        for j in zj:
            jn = POSTURE_JOINTS[j]
            out.append(float(c[names.index(f"{side}_{jn}_pos")] - c[names.index(f"{side}_{jn}_neg")]))
        return out

    def contacts(self):
        """(forces on the ball in ball weights: dict floor / l / r / body)"""
        m, d = self.m, self.d
        out = {"floor": 0.0, "l": 0.0, "r": 0.0, "body": 0.0}
        nc = d.ncon
        if nc == 0:
            return out
        g1 = d.contact.geom1[:nc]
        g2 = d.contact.geom2[:nc]
        sel = np.nonzero((g1 == self.ball_geom) | (g2 == self.ball_geom))[0]
        f6 = self._f6
        for i in sel:
            o = g2[i] if g1[i] == self.ball_geom else g1[i]
            mujoco.mj_contactForce(m, d, int(i), f6)
            fn = abs(f6[0]) / self.w
            if o == self.floor_geom:
                out["floor"] += fn
            elif o in self.hand_geoms:
                out[self.hand_geoms[o]] += fn
            else:
                out["body"] += fn
        return out

    def run(self, override=None, ticks=None, start=None, stop=None, hand_col=None):
        """Replay from the snapshot for `ticks` control ticks (default: to the end of the recording). `override` maps a
        muscle index to an array of activations per tick (from the snapshot's tick); other muscles replay the recording.
        Returns the trace dict: per tick the ball position/velocity, contact forces (l, r, floor, body)."""
        rec = self.rec
        k0 = rec["k0"] if start is None else start
        n = (len(rec["acts"]) - k0) if ticks is None else ticks
        self.load(start)
        d, m = self.d, self.m
        base = rec["acts"]
        ids = self.act_ids
        pos = np.zeros((n, 3))
        vel = np.zeros((n, 3))
        cf = np.zeros((n, 4))
        legs = np.zeros((n, 2, 3, 3))
        palm = np.zeros((n, 2, 3))
        prehit = np.zeros(n)
        for i in range(n):
            a = base[k0 + i].copy()
            if override:
                for mi, arr in override.items():
                    a[mi] = arr[i]
            d.ctrl[ids] = a
            fm = [0.0, 0.0, 0.0, 0.0]
            sb = sh = -1
            for sub in range(SUBSTEPS):
                mujoco.mj_step(m, d)
                f = self.contacts()
                for j, key in enumerate(("l", "r", "floor", "body")):
                    if f[key] > fm[j]:
                        fm[j] = f[key]
                if f["body"] > 0.3 and sb < 0:
                    sb = sub
                if hand_col is not None and f["lr"[hand_col]] > 0.3 and sh < 0:
                    sh = sub
            pos[i] = d.xpos[self.ball_id]
            vel[i] = d.qvel[self.ball_dof:self.ball_dof + 3]
            cf[i] = fm
            # within this tick the arm/body touched the ball before the hand did
            prehit[i] = 1.0 if (sb >= 0 and sh >= 0 and sb < sh) else 0.0
            for si in range(2):
                for ji in range(3):
                    legs[i, si, ji] = d.xpos[self.leg_ids[si][ji]]
                palm[i, si] = d.site_xpos[self.palm_ids[si]]
            if stop is not None and stop(i, pos, vel, cf):
                n = i + 1
                break
        pos, vel, cf, legs, palm, prehit = pos[:n], vel[:n], cf[:n], legs[:n], palm[:n], prehit[:n]
        return {"pos": pos, "vel": vel, "cf": cf, "legs": legs, "palm": palm, "prehit": prehit, "t0": (rec["snap"] if start is None else rec["snaps"][start])[4]}
