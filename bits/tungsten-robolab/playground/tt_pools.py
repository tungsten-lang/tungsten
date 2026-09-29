"""Serve pools by side (round 10): which seeds the champion's side rule sends to the forehand or the backhand.

The side rule (MyoTTSkill#choose_side, side_mode 0, y_switch 0.1) picks the backhand when the ball's predicted crossing of
the pad's start plane (x 1.91) is left of y_switch. This reproduces it from each seed's launch state (env reset only, no
controller) so forehand-only or backhand-only screens can use serves that all exercise the side under test.

    .venv-myo/bin/python playground/tt_pools.py --seed0 740000 --n 2000 --out out/tt_r10/pools_740000.json
"""
import argparse
import json
import os
import sys
import warnings

import numpy as np

warnings.filterwarnings("ignore")
os.environ.setdefault("TT_ENV", "P2")
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)


def cross(p, v, xh=1.91):
    px, py, pz = p
    vx, vy, vz = v
    disc = vz * vz + 2 * 9.81 * (pz - 0.805)
    tb = (vz + np.sqrt(disc)) / 9.81
    px, py = px + vx * tb, py + vy * tb
    vz = -(vz - 9.81 * tb) * 0.99
    vx, vy = vx * 0.996, vy * 0.996
    th = (xh - px) / vx
    return py + vy * th, tb + th


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed0", type=int, default=740000)
    ap.add_argument("--n", type=int, default=2000)
    ap.add_argument("--out", required=True)
    ap.add_argument("--y_switch", type=float, default=0.1)
    a = ap.parse_args()
    from myosuite.utils import gym
    env = gym.make("myoChallengeTableTennisP2-v0", normalize_act=True) if False else gym.make("myoChallengeTableTennisP2-v0")
    u = env.unwrapped
    m = u.mj_model
    adr = m.jnt_qposadr[m.joint("pingpong_freejoint").id]
    dof = m.jnt_dofadr[m.joint("pingpong_freejoint").id]
    out = {"fh": [], "bh": [], "y": {}}
    for s in range(a.seed0, a.seed0 + a.n):
        u.seed(s)
        env.reset(seed=s)
        p = u.mj_data.qpos[adr:adr + 3].copy()
        v = u.mj_data.qvel[dof:dof + 3].copy()
        y, t = cross(p, v)
        out["y"][s] = round(float(y), 4)
        (out["bh"] if y < a.y_switch else out["fh"]).append(s)
    json.dump(out, open(a.out, "w"))
    print(f"forehand {len(out['fh'])}, backhand {len(out['bh'])} of {a.n}")


if __name__ == "__main__":
    main()
