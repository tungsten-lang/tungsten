"""Saved-state replays WITH the controller in the loop.

A dump (kladder.py --dump) holds, per tick of a full episode, the sensor line S sent to the controller, its reply A and the physics
state. `replay(pack, k, params, controller)` restores the physics to tick k, starts a FRESH controller process with `params`,
feeds it the recorded sensor lines of ticks 0..k-1 (its internal state is a deterministic function of params and that stream, so it
arrives at tick k exactly as the original did when `params` equal the original's up to that point), then runs the episode live from tick k.

A candidate whose behaviour differs from the dump's only from tick k on (e.g. a closed-loop swing gated on the phase 'swing')
is therefore a faithful test of that change from a checkpoint, in ~1-2 s instead of a full rollout.
Identity check: `kreplay.py --check PACK` (same params, same binary: the outcome must be bit-identical to the dump).
"""
import argparse
import glob
import gzip
import math
import os
import pickle
import sys
import time

import numpy as np

sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/kick")
import kcommon as K

CK = "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/kick/ckpt/"


def load(path):
    with gzip.open(path, "rb") as f:
        return pickle.load(f)


def first_tick(pack, lab):
    return next((i for i, r in enumerate(pack["trace"]) if r["lab"] == lab), None)


class Worker:
    """One MyoSim per process, reused for every replay (the pack's own muscle geometry is swapped in)."""

    def __init__(self, controller=None):
        K.ensure()
        self.controller = controller or K.P1_CTL
        self.sim = K.make_sim({}, self.controller, 5000, dict(noise=0.0, dx=0.0, dy=0.0))
        self.sim.record = False

    def rewind(self, seed):
        sim = self.sim
        w = sim.env
        while w is not None and w is not sim.u:
            if hasattr(w, "_elapsed_steps"):
                w._elapsed_steps = 0
            w = getattr(w, "env", None)
        sim.u.seed(seed)
        sim.env.reset(seed=seed)
        task = sim.task
        task.reset_stats()
        task._sim = sim
        sim.label = ""
        sim.log, sim.infos = [], []
        sim.S_hist, sim.A_hist, sim.state_hist = [], [], []

    def replay(self, pack, k, params, controller=None, max_after_touch=1.7, max_after_k=2.6, check=True, feed_from=0):
        sim = self.sim
        self.rewind(pack["seed"])
        sim.set_geometry(pack["geometry"])
        sim.params = dict(params)
        if controller is not None:
            sim.controller_cmd = [controller, sim.skill]
        sim.restore(pack["state"][k])
        sim.start_controller()
        bad, worst = 0, 0.0
        S, A = pack["S"], pack["A"]
        try:
            for j in range(k):
                sim.proc.stdin.write(S[j])
                sim.proc.stdin.flush()
                line = sim.proc.stdout.readline()
                if check and line != A[j]:
                    bad += 1
                    try:
                        a = np.array([float(x) for x in line.split()[1:291]])
                        b = np.array([float(x) for x in A[j].split()[1:291]])
                        worst = max(worst, float(np.max(np.abs(a - b))))
                    except Exception:
                        worst = 9.0
            t_start = float(sim.d.time)
            steps = 0
            task = sim.task
            term = trunc = False
            while True:
                act, c = sim.tick()
                obs, reward, term, trunc, info = sim.env.step(sim.action_from(act))
                steps += 1
                sim.infos.append(info)
                task.on_step(sim, obs, reward, info)
                if term or trunc:
                    break
                t = float(sim.d.time)
                if task.touch_t is not None and t > task.touch_t + max_after_touch:
                    break
                if t > t_start + max_after_k:
                    break
        finally:
            sim.stop_controller()
        m = task.metrics(sim, [])
        m["steps"] = steps
        m["replay_bad"] = bad
        m["replay_worst"] = worst
        m["trace"] = task.tr
        return m


def kick_ok(m):
    """the ball leaves fast, will cross inside the window (|y| in [0.5, 3.2]), the kicker is up until it crosses (or the goal was scored)."""
    if m.get("goal"):
        return True
    sp = m.get("ball_speed") or 0.0
    cy = m.get("cross_y", m.get("pred_y"))
    if cy is None or sp < 8.5 or not (0.5 < abs(cy) < 3.2):
        return False
    if m.get("fallen") and m.get("t_cross") is None:
        return False
    return True


def score(m):
    """shaped score of a replay (higher is better): goal 10, then touch, speed, window, staying up."""
    s = 0.0
    if m.get("t_touch") is None:
        return -1.0 - min(m.get("r_toe_ball_min", 1.0), 1.0)
    s += 1.0 + 0.3 * min(m.get("ball_speed", 0.0), 13.0)
    cy = m.get("cross_y", m.get("pred_y"))
    if cy is not None:
        a = abs(cy)
        s += 3.0 * max(0.0, 1.0 - max(0.0, 0.5 - a) / 0.5) * max(0.0, 1.0 - max(0.0, a - 3.2) / 2.0)
    tf = m.get("t_fall")
    if tf is not None:
        s += 2.0 * min(max(tf - m["t_touch"], 0.0) / 1.3, 1.0)
    else:
        s += 2.0
    return s + (10.0 if m.get("goal") else 0.0)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", nargs="+", help="dump files: replay from the swing start with the dump's own params")
    ap.add_argument("--lead", type=int, default=2, help="ticks before the first 'swing' tick")
    a = ap.parse_args()
    w = Worker()
    for path in a.check:
        pack = load(path)
        k = first_tick(pack, "swing") - a.lead
        t0 = time.time()
        m = w.replay(pack, k, pack["params"], controller=pack["controller"])
        row = pack["row"]
        print(f"{os.path.basename(path)[:40]:40s} k {k} replay_bad {m['replay_bad']} worst {m['replay_worst']:.2g} | speed {m['ball_speed']} (dump {row['ball_speed']}) touch {m['t_touch']} (dump {row['t_touch']}) "
              f"cross_y {m.get('cross_y')} (dump {row['cross_y']}) fallen {m['fallen']} (dump {row['fallen']}) goal {m['goal']} ({time.time()-t0:.1f}s)", flush=True)
