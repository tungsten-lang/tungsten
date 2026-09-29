"""Run one soccer start and CAPTURE the exact simulator state before a MuJoCo instability warning.

usage: capture.py --params P --controller C --seed S --seconds T --out DIR [--set k=v,...] [--ring N] [--full]

Runs the same rollout the arena runs (MyoSim + MyoSoccerTask, MYO_SOCCER_ENV=myoChallengeSoccerP2-v0, MYO_SOCCER_MAX_TIME=310) with a
MuJoCo user-warning callback. A ring buffer keeps mj_getState(mjSTATE_INTEGRATION) (time, qpos, qvel, act, warmstart, ctrl, eq_active,
mocap, ...) after every control step (100 Hz). When MuJoCo raises a warning (the instability), the callback (which runs INSIDE mj_step
before mj_resetData) saves: the ring, the failing step's ctrl, the bad step's qacc / efc / contact tables, and the model as an .mjb, into
DIR/. The run stops at the first control step after the warning. No warning -> the ring of the last N steps is saved when the run ends.

DIR/model.mjb          the model of the run (mj_saveModel), so replays need only mujoco + numpy
DIR/ring.npz           t (n,), state (n, nstate), spec: the STEPPED MjData (sim.u.robot.mj_data; MyoSuite's env.mj_data is only a
                       mirror synced from it once per control step, with ctrl = 0 and no warmstart) after control step k, incl. the ctrl of step k
DIR/fail.npz           the failing substep's data (only if a warning fired)
DIR/summary.json       seed, params file, controller, blow-up time, versions
"""
import argparse
import collections
import json
import os
import sys
import time

import numpy as np

HERE = "/Users/erik/tungsten/bits/tungsten-robolab"
sys.path.insert(0, os.path.join(HERE, "playground"))
sys.path.insert(0, os.path.join(HERE, "scratchpad", "soccer4"))
os.environ.setdefault("MYO_SOCCER_ENV", "myoChallengeSoccerP2-v0")
os.environ.setdefault("MYO_SOCCER_MAX_TIME", "310")
import mujoco  # noqa: E402
from search4 import read_params  # noqa: E402
from myo_bridge import MyoSim  # noqa: E402
from tasks.myo_soccer import MyoSoccerTask  # noqa: E402

SPEC = int(mujoco.mjtState.mjSTATE_INTEGRATION)


class Blown(Exception):
    pass


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--params", required=True)
    ap.add_argument("--controller", required=True)
    ap.add_argument("--seed", type=int, required=True)
    ap.add_argument("--seconds", type=float, required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--set", default="")
    ap.add_argument("--ring", type=int, default=2000)
    ap.add_argument("--stop_after", type=int, default=3, help="control steps to keep running after the warning")
    a = ap.parse_args()
    params = read_params(a.params)
    for kv in a.set.split(","):
        if "=" in kv:
            k, v = kv.split("=")
            params[k.strip()] = float(v)
    ctl = os.path.abspath(a.controller)
    os.makedirs(a.out, exist_ok=True)

    ring_t = collections.deque(maxlen=a.ring)
    ring_s = collections.deque(maxlen=a.ring)
    holder = {"warn": None, "after": 0}
    t0 = time.time()

    def save_fail(msg):
        sim = holder["sim"]
        m, d = sim.m, sim.u.robot.mj_data  # the STEPPED data: MyoSuite's env.mj_data is only a sensor-synced mirror
        fail = {}
        for name in ("qpos", "qvel", "act", "qacc", "qacc_smooth", "qacc_warmstart", "qfrc_smooth", "qfrc_constraint",
                     "qfrc_actuator", "qfrc_passive", "qfrc_bias", "qfrc_spring", "qfrc_damper", "qfrc_gravcomp",
                     "actuator_force", "actuator_length", "actuator_velocity", "act_dot", "ctrl", "ten_length", "ten_velocity",
                     "efc_type", "efc_id", "efc_pos", "efc_margin", "efc_D", "efc_R", "efc_aref", "efc_force", "efc_vel",
                     "efc_frictionloss", "efc_KBIP"):
            try:
                fail[name] = np.array(getattr(d, name)).copy()
            except Exception as e:  # attribute missing in this build
                fail[name] = np.array([np.nan])
        print(f"callback: stepped data time {d.time:.4f} ncon {d.ncon} nefc {d.nefc} max|ctrl| {np.abs(d.ctrl).max():.3f} max|qacc| {np.nanmax(np.abs(d.qacc)):.4g}", flush=True)
        fail["time"] = np.array([d.time])
        fail["ncon"] = np.array([d.ncon])
        fail["nefc"] = np.array([d.nefc])
        fail["solver_niter"] = np.array(d.solver_niter).copy()
        try:
            fail["solver_fwdinv"] = np.array(d.solver_fwdinv).copy()
        except Exception:
            pass
        rows = []
        for i in range(d.ncon):
            c = d.contact[i]
            f6 = np.zeros(6)
            mujoco.mj_contactForce(m, d, i, f6)
            rows.append([c.geom1, c.geom2, c.dist, *c.pos, *c.frame[:3], c.efc_address, *f6[:3], c.dim, c.mu, c.includemargin])
        fail["contacts"] = np.array(rows, dtype=float).reshape(-1, 16)
        np.savez_compressed(os.path.join(a.out, "fail.npz"), **fail)
        holder["warn"] = {"msg": msg, "time": float(d.time), "ctrl_fail_saved": True}
        holder["ctrl_fail"] = d.ctrl.copy()
        holder["t_fail"] = float(d.time)

    def on_warn(msg):
        print("MUJOCO WARNING:", msg, flush=True)
        if holder["warn"] is None and "sim" in holder:
            save_fail(msg)

    mujoco.set_mju_user_warning(on_warn)

    class T(MyoSoccerTask):
        def on_step(self, sim, obs, reward, info):
            super().on_step(sim, obs, reward, info)
            m, d = sim.m, sim.u.robot.mj_data  # the stepped data (sim.d is a mirror: ctrl 0, no warmstart)
            holder["sim"] = sim
            if holder["warn"] is not None:
                holder["after"] += 1
                if holder["after"] >= a.stop_after:
                    raise Blown()
                return
            st = np.zeros(mujoco.mj_stateSize(m, SPEC))
            mujoco.mj_getState(m, d, st, SPEC)
            ring_t.append(float(d.time))
            ring_s.append(st)

    sim = MyoSim(T(), params=params, controller=ctl, seed=a.seed)
    holder["sim"] = sim
    m = sim.m
    mujoco.mj_saveModel(m, os.path.join(a.out, "model.mjb"))
    res = {}
    try:
        res = sim.run(a.seconds)
    except Blown:
        pass
    wall = time.time() - t0
    n = len(ring_t)
    st = np.array(ring_s) if n else np.zeros((0, 1))
    np.savez_compressed(os.path.join(a.out, "ring.npz"), t=np.array(ring_t), state=st, spec=SPEC,
                        ctrl_fail=holder.get("ctrl_fail", np.zeros(0)), t_fail=holder.get("t_fail", -1.0))
    summ = {"seed": a.seed, "params": os.path.abspath(a.params), "set": a.set, "controller": ctl, "seconds": a.seconds,
            "warning": holder["warn"], "ring_n": n, "ring_t0": float(ring_t[0]) if n else None,
            "ring_t1": float(ring_t[-1]) if n else None, "wall_s": round(wall, 1),
            "mujoco": mujoco.__version__, "result": {k: res.get(k) for k in ("bal1_s", "stand_time", "fallen", "time")}}
    with open(os.path.join(a.out, "summary.json"), "w") as f:
        json.dump(summ, f, indent=1)
    print(json.dumps(summ), flush=True)


if __name__ == "__main__":
    main()
