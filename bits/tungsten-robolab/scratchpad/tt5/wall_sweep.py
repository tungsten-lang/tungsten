#!/usr/bin/env python3
"""Hit the ball at every position of its path, at many pad angles and speeds, with the real physics (Erik, 3 Oct 2026: "slice up the ball's path and hit the ball at each position ... for each
position, test various angles, paddle orientations, speeds").  Oracle mode o4 (the KINEMATIC paddle, `o4`): for serve SEED, slice j of the ball's free path (the champion's own log: ball centre
p_j and velocity v_j at tick t_j), pad orientation (pitch, yaw) and pad speed s (the pad moves at s m/s along +x, away from the net: a retreat softens the return), the paddle is puppeted so that its
face meets the ball centre at t_j (P = p_j - 0.04 n_out, plan convention of scratchpad/tt3/make_plans.py); the ball meets the pad disc through the environment's own contact model and `solved` is the
environment's. LABELLED DIAGNOSTIC ORACLE: a rigid wall at an exact place, never comparable with the official trial.
    TT_ENV=P2 .venv-myo/bin/python scratchpad/tt5/wall_sweep.py SEEDS [--xrange 1.3:2.6] [--tick-step 4] [--out out/tt5/wall.jsonl] [--workers 6]      from bits/tungsten-robolab"""
import argparse
import json
import os
import sys

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.chdir(ROOT)
os.environ["TT_ENV"] = "P2"
os.environ["TT_TASK"] = "myo_tt_oracle"
os.environ["MYO_TT_ORACLE"] = "o4"
sys.path.insert(0, os.path.join(ROOT, "playground"))
sys.path.insert(0, os.path.join(ROOT, "scratchpad", "tt5"))
PARAMS = "params/myo_tt_p2_r10_c3.txt"
CONTROLLER = "bin/challengers/myo_tt_r10-n"
PITCH = [-30, -20, -10, 0, 10, 20, 30, 40]
YAW = [-30, -20, -10, 0, 10, 20, 30]
SPEED = [0.0, 1.0, 2.0]


def normal(pitch_deg, yaw_deg):
    p, y = np.radians(pitch_deg), np.radians(yaw_deg)
    return np.array([np.cos(p) * np.cos(y), np.cos(p) * np.sin(y), np.sin(p)])


def free_ticks(seed, xr, step):
    z = np.load(f"out/tt3/logs_o0/{seed}.npz", allow_pickle=True)
    L, k = z["L"], int(z["contact"])
    end = len(L) if k < 0 else max(k, 1)           # the ball's own path: the whole log of a miss, the ticks before the contact otherwise
    js = [j for j in range(end) if xr[0] <= L[j, 1] <= xr[1] and L[j, 3] > 0.5 and (j % step == 0)]
    return L, js


def main():
    import tt_fast
    ap = argparse.ArgumentParser()
    ap.add_argument("seeds")
    ap.add_argument("--xrange", default="1.3:2.6")
    ap.add_argument("--tick-step", type=int, default=4)
    ap.add_argument("--out", default="out/tt5/wall.jsonl")
    ap.add_argument("--workers", type=int, default=6)
    a = ap.parse_args()
    xr = tuple(float(x) for x in a.xrange.split(":"))
    params = tt_fast.read_params(PARAMS)
    ctl = os.path.abspath(CONTROLLER)
    done = set()
    if os.path.exists(a.out):
        for l in open(a.out):
            r = json.loads(l)
            done.add((r["seed"], r["j"], r["pitch"], r["yaw"], r["speed"]))
    jobs, keys = [], []
    for sd in [int(x) for x in a.seeds.split(",")]:
        L, js = free_ticks(sd, xr, a.tick_step)
        for j in js:
            for pitch in PITCH:
                for yaw in YAW:
                    n_out = -normal(pitch, yaw)
                    for s in SPEED:
                        if (sd, j, pitch, yaw, s) in done:
                            continue
                        plan = {"t_hit": float(L[j, 0]), "P": (L[j, 1:4] - 0.04 * n_out).tolist(), "n_out": n_out.tolist(), "v": [s, 0.0, 0.0],
                                "t_on": float(L[j, 0]) - 0.15, "t_off": float(L[j, 0]) + 0.15}
                        jobs.append((params, sd, None, ctl, {"orc_plan": plan}))
                        keys.append(dict(seed=sd, j=j, t=float(L[j, 0]), ball=[round(float(x), 3) for x in L[j, 1:4]], vball=[round(float(x), 3) for x in L[j, 4:7]], pitch=pitch, yaw=yaw, speed=s))
    print(f"{len(jobs)} rollouts to run ({len(done)} done)", flush=True)
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    with open(a.out, "a") as f:
        pool = tt_fast.pool(a.workers)
        for key, r in zip(keys, pool.imap(tt_fast.episode, jobs, chunksize=2)):
            key.update(error=r.get("error"), hit=r.get("hit"), solved=r.get("solved"), landed=r.get("landed"), land_xy=r.get("land_xy"))
            f.write(json.dumps(key) + "\n")
            f.flush()


if __name__ == "__main__":
    main()
