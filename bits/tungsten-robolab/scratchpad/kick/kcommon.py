"""Shared tools of the penalty-kick campaign (agent P, 9/29): a MyoSim with a controllable reset, per-step
traces, the sensor stream and MuJoCo state history, and saved-state replays.

Everything here runs in .venv-myo. State lives in the repo (scratchpad/kick/), never /private/tmp.

The reset. p1probe.py (agent O) replaced the P2 reset by "the P1 key frame + noise x the P2 draw + a root
offset"; `reset_kw` does the same: dict(noise=, dx=, dy=) (noise scales the env's own +-0.02 rad joint draw,
dx/dy move the root from the key frame's (39, 0); dx=None uses the P2 draw's own root position).
"""
import os
import sys
import json
import math
import time
import pickle

import numpy as np

REPO = "/Users/erik/tungsten/bits/tungsten-robolab"
sys.path.insert(0, REPO + "/playground")
os.environ.setdefault("MUJOCO_GL", "cgl")

P1_CTL = REPO + "/bin/champions/soccer_p1-20260926-151503"
P1_PARAMS = REPO + "/playground/arena/params/soccer_p1-20260926-151503.txt"


def read_params(path):
    out = {}
    for line in open(path):
        p = line.split()
        if len(p) >= 2 and not line.startswith("#"):
            out[p[0]] = float(p[1])
    return out


def write_params(path, params, header=()):
    with open(path, "w") as f:
        for h in header:
            f.write("# " + h + "\n")
        for k in sorted(params):
            if not k.startswith("__"):
                f.write(f"{k} {float(params[k])!r}\n")


_Q_P1 = None


def p1_keyframe():
    """qpos of the P1 reset (the model's key frame 0)."""
    global _Q_P1
    if _Q_P1 is None:
        from myosuite.utils import gym as mgym
        e1 = mgym.make("myoChallengeSoccerP1-v0")
        e1.reset(seed=0)
        _Q_P1 = e1.unwrapped.mj_data.qpos.copy()
    return _Q_P1


class KSim:
    """Factory namespace: builds a MyoSim (with the task's per-step trace) for one episode."""


def make_sim(params, controller, seed, reset_kw=None, env="myoChallengeSoccerP2-v0", trace=True, max_time=None):
    """A MyoSim for one episode. reset_kw None = the official P2 reset; else dict(noise, dx, dy)."""
    ensure(env, max_time)
    from myosuite.utils import gym as mgym
    import myo_bridge
    from myo_bridge import MyoSim
    import importlib
    tmod = importlib.import_module("tasks.myo_soccer")
    task = KTask() if trace else tmod.MyoSoccerTask()
    if reset_kw is None:
        sim = KMyoSim(task, params=params, controller=controller, seed=seed)
        return sim
    q_p1 = p1_keyframe()
    orig_make = mgym.make
    noise = reset_kw.get("noise", 1.0)
    dx, dy = reset_kw.get("dx", 0.0), reset_kw.get("dy", 0.0)
    # groups: only joints whose name contains one of these substrings get the noise (None: all)
    groups = reset_kw.get("groups")

    def make2(*a, **k):
        e = orig_make(*a, **k)
        u = e.unwrapped
        orig_grs = u._get_reset_state

        def grs():
            qn, qv = orig_grs()
            m = u.mj_model
            q = q_p1.copy()
            for j in range(m.njnt):
                if m.jnt_type[j] in (2, 3):
                    adr = m.jnt_qposadr[j]
                    nm_ = m.joint(j).name
                    if groups is not None and not any((g[1:] == nm_) if g.startswith("=") else (g in nm_) for g in groups):
                        continue
                    q[adr] = q_p1[adr] + noise * (qn[adr] - q_p1[adr])
            ra = m.jnt_qposadr[m.joint("root").id]
            if dx is None:
                q[ra], q[ra + 1] = qn[ra], qn[ra + 1]
            else:
                q[ra] = q_p1[ra] + dx
                q[ra + 1] = q_p1[ra + 1] + dy
            return q, np.zeros_like(qv)
        u._get_reset_state = grs
        return e
    mgym.make = make2
    try:
        sim = KMyoSim(task, params=params, controller=controller, seed=seed)
    finally:
        mgym.make = orig_make
    return sim


def _base():
    from myo_bridge import MyoSim
    return MyoSim


def _task_base():
    import importlib
    return importlib.import_module("tasks.myo_soccer").MyoSoccerTask


class _Lazy:
    pass


def _define():
    """Classes that subclass MyoSim / MyoSoccerTask: defined after the env id is set (import time matters:
    MyoSoccerTask.env_id is read from the environment when its module is first imported)."""
    global KMyoSim, KTask
    MyoSim = _base()
    Task = _task_base()

    class KTask(Task):
        """MyoSoccerTask plus a per-step trace (t, phase, ball, feet, pelvis, COM)."""

        def reset_stats(self):
            super().reset_stats()
            self.tr = []

        def on_step(self, sim, obs, reward, info):
            super().on_step(sim, obs, reward, info)
            m, d = sim.m, sim.d
            i = self.ids(m)
            lab = sim.label.split(":")[-1] if sim.label else ""
            pel = d.xmat[i["pelvis"]].reshape(3, 3)
            self.tr.append({
                "t": float(d.time), "lab": lab,
                "ball": d.xpos[i["ball"]].copy(), "bvel": d.qvel[i["bv"]:i["bv"] + 3].copy(),
                "toe_r": d.xpos[i["toes_r"]].copy(), "toe_l": d.xpos[i["toes_l"]].copy(),
                "ank_r": d.xpos[i["talus_r"]].copy(), "ank_l": d.xpos[i["talus_l"]].copy(),
                "hip_r": d.xpos[i["femur_r"]].copy(), "hip_l": d.xpos[i["femur_l"]].copy(),
                "bof_r": d.geom_xpos[m.geom("r_bofoot").id].copy(),
                "vtoe_r": self.body_vel(m, d, i["toes_r"]), "vank_r": self.body_vel(m, d, i["talus_r"]),
                "pelvis": d.xpos[i["pelvis"]].copy(), "yaw": math.atan2(pel[1, 0], pel[0, 0]),
                "com": d.subtree_com[m.body("root").id].copy(),
                "keeper": float(d.mocap_pos[0, 1]),
            })

    class KMyoSim(MyoSim):
        """MyoSim that keeps the sensor stream, the replies and the MuJoCo state of every tick, so an episode can
        be replayed from any tick (the controller re-fed the recorded sensors, the physics restored)."""

        def __init__(self, *a, **k):
            super().__init__(*a, **k)
            if os.environ.get("KICK_NOLEGCOL") == "1":
                # diagnostic only (never used for scores): the two legs no longer collide with each other (contype 2 / conaffinity 1 on both legs)
                m = self.m
                for nm in ("femur", "tibia", "talus", "calcn", "toes"):
                    for sd in ("_l", "_r"):
                        b = m.body(nm + sd).id
                        for g in range(m.body_geomadr[b], m.body_geomadr[b] + m.body_geomnum[b]):
                            m.geom_contype[g] = 2
                            m.geom_conaffinity[g] = 1
                # the model lists explicit contact pairs between the thighs and shanks (they collide whatever contype says): switch them off
                # with a margin no distance can meet
                for k in range(m.npair):
                    m.pair_margin[k] = -1000.0
            self.S_hist, self.A_hist, self.state_hist = [], [], []
            self.record = True
            self.geom_pack = None

        def phys(self):
            """The physics MjData. MyoSuite keeps the true state in robot.mj_data; env.mj_data (== the bridge's sim.d)
            is a mirror rebuilt from the sensors after every step (qpos, qvel, act, time and a forward pass), so ctrl,
            the solver's warm start and the physical goalkeeper mocap must be read and written on robot.mj_data."""
            return self.u.robot.mj_data

        def snapshot(self):
            p = self.phys()
            return {"qpos": p.qpos.copy(), "qvel": p.qvel.copy(), "act": p.act.copy(), "ctrl": p.ctrl.copy(),
                    "warm": p.qacc_warmstart.copy(), "time": float(p.time),
                    "mocap_pos": p.mocap_pos.copy(), "mocap_quat": p.mocap_quat.copy(),
                    "keeper_pos": self.d.mocap_pos.copy(), "keeper_quat": self.d.mocap_quat.copy()}

        def restore(self, st):
            p = self.phys()
            p.qpos[:] = st["qpos"]
            p.qvel[:] = st["qvel"]
            p.act[:] = st["act"]
            p.ctrl[:] = st["ctrl"]
            p.qacc_warmstart[:] = st["warm"]
            p.time = st["time"]
            p.mocap_pos[:] = st["mocap_pos"]
            p.mocap_quat[:] = st["mocap_quat"]
            import mujoco
            mujoco.mj_forward(self.m, p)
            # the mirror: rebuilt from the sensors (forward), then the observed keeper's pose
            self.u.forward()
            self.d.mocap_pos[:] = st["keeper_pos"]
            self.d.mocap_quat[:] = st["keeper_quat"]

        def tick(self):
            if self.record:
                self.state_hist.append(self.snapshot())
            c, cd, f = self.contraction()
            vals = [self.d.time, *c, *cd, *f]
            for _, v in self.sensor_blocks():
                vals.extend(np.asarray(v, dtype=float).ravel())
            sline = "S " + " ".join(f"{x:.7g}" for x in vals) + "\n"
            self.proc.stdin.write(sline)
            self.proc.stdin.flush()
            line = self.proc.stdout.readline()
            if not line.startswith("A "):
                err = self.proc.stderr.read() if self.proc.stderr else ""
                raise RuntimeError(f"controller reply {line!r}\n{err}")
            if self.record:
                self.S_hist.append(sline)
                self.A_hist.append(line)
            tok = line.split()
            n = self.n
            act = np.clip(np.array([float(x) for x in tok[1:1 + n]]), 0.0, 1.0)
            self.targets = np.array([float(x) for x in tok[1 + n:1 + 2 * n]])
            self.label = tok[1 + 2 * n] if len(tok) > 1 + 2 * n else ""
            for cmd in tok[2 + 2 * n:]:
                if cmd.startswith("motor:"):
                    _, name, value = cmd.split(":")
                    self.motor_cmd[name] = float(value)
                else:
                    self.task.on_command(self, cmd)
            return act, c

        def geometry_pack(self):
            return {"joints": self.joints, "table": self.table, "lref": self.lref, "pairs": self.pairs,
                    "lr": self.lr}

        def set_geometry(self, pack):
            self.joints, self.table, self.lref, self.pairs = pack["joints"], pack["table"], pack["lref"], pack["pairs"]

        def replay_from(self, k, S_hist, A_hist=None, max_seconds=None, check=True):
            """Restore the physics to tick k's state (self.state_hist[k] must hold it) after feeding a fresh
            controller the recorded sensors of ticks 0..k-1; then run live to the end of the episode. Returns
            (metrics, mismatch): the number of replies during the fed part that differ from A_hist (a fresh
            controller with the same params must repeat its old replies exactly)."""
            self.start_controller()
            bad = 0
            worst = 0.0
            for j in range(k):
                self.proc.stdin.write(S_hist[j])
                self.proc.stdin.flush()
                line = self.proc.stdout.readline()
                if check and A_hist is not None and line != A_hist[j]:
                    bad += 1
                    try:
                        a = np.array([float(x) for x in line.split()[1:291]])
                        b = np.array([float(x) for x in A_hist[j].split()[1:291]])
                        worst = max(worst, float(np.max(np.abs(a - b))))
                    except Exception:
                        worst = 9.0
            self.replay_bad = (bad, worst)
            return bad, worst

        def run_live(self, seconds=None):
            """The MyoSim.run loop without start_controller (the controller is already running)."""
            solved = sparse = dense = 0.0
            steps = 0
            terminated = False
            try:
                while True:
                    act, c = self.tick()
                    obs, reward, term, trunc, info = self.env.step(self.action_from(act))
                    steps += 1
                    solved = max(solved, float(info.get("solved", 0.0)))
                    self.infos.append(info)
                    self.task.on_step(self, obs, reward, info)
                    if term or trunc:
                        terminated = bool(term)
                        break
                    if seconds and self.d.time >= seconds:
                        break
            finally:
                self.stop_controller()
            out = {"steps": steps, "time": round(float(self.d.time), 3), "solved": solved, "terminated": terminated}
            out.update(self.task.metrics(self, self.log))
            return out

    globals()["KMyoSim"] = KMyoSim
    globals()["KTask"] = KTask


KMyoSim = None
KTask = None


def ensure(env="myoChallengeSoccerP2-v0", max_time=None):
    os.environ["MYO_SOCCER_ENV"] = env
    if max_time is not None:
        os.environ["MYO_SOCCER_MAX_TIME"] = str(max_time)
    if KMyoSim is None or globals().get("_ENV") != (env, max_time):
        # tasks.myo_soccer reads MYO_SOCCER_ENV at import: import after setting it
        import importlib
        if "tasks.myo_soccer" in sys.modules:
            importlib.reload(sys.modules["tasks.myo_soccer"])
        _define()
        globals()["_ENV"] = (env, max_time)


def run_episode(params, controller, seed, reset_kw=None, seconds=6.0, env="myoChallengeSoccerP2-v0", record=True):
    """One full episode with the trace; returns (metrics, sim)."""
    ensure(env)
    sim = make_sim(params, controller, seed, reset_kw, env=env)
    sim.record = record
    m = sim.run(seconds)
    return m, sim


def touch_index(sim):
    """First trace index with ball contact (task.touch_t), or None."""
    t = sim.task.touch_t
    if t is None:
        return None
    for j, r in enumerate(sim.task.tr):
        if r["t"] >= t - 1e-9:
            return j
    return None
