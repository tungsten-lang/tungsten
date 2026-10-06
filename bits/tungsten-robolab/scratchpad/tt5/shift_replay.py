#!/usr/bin/env python3
"""Timing test with the real physics (Erik, 3 Oct 2026): replay the champion's OWN recorded stroke (pad centre and normal at every 10 ms tick, oracle mode o8) time-shifted against the same ball path.
shift < 0: the pad arrives EARLIER than it did; shift > 0: LATER. For each serve and shift: did the pad touch the ball, was the return legal ('solved'), where did it land.
A solved serve is expected to stay solved at shift 0 (the replay is rigid: no recoil); the question is how the outcome moves with the shift.
    TT_ENV=P2 .venv-myo/bin/python scratchpad/tt5/shift_replay.py SEEDS [--shifts -0.1:0.1:0.01] [--out out/tt5/shift.jsonl] [--workers 6]       from bits/tungsten-robolab
SEEDS: a comma list, or the words miss / touched / solved / all (classes of sets A + B for the plain champion). A file with a __main__ guard (multiprocessing spawn)."""
import argparse
import json
import os
import sys

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.chdir(ROOT)
os.environ["TT_ENV"] = "P2"
os.environ["TT_TASK"] = "myo_tt_oracle"
os.environ["MYO_TT_ORACLE"] = "o8"
sys.path.insert(0, os.path.join(ROOT, "playground"))
PARAMS = "params/myo_tt_p2_r10_c3.txt"
CONTROLLER = "bin/challengers/myo_tt_r10-n"


def classes():
    rows = {}
    for s in ("A", "B"):
        for l in open(f"out/tt3/o0_{s}.jsonl"):
            r = json.loads(l)
            rows[r["seed"]] = r
    cl = {}
    for sd, r in rows.items():
        k = int(np.load(f"out/tt3/logs_o0/{sd}.npz", allow_pickle=True)["contact"])
        cl[sd] = "solved" if r.get("solved", 0) > 0 else ("touched" if k >= 0 else "miss")
    return cl


def traj(seed):
    z = np.load(f"out/tt3/logs_o0/{seed}.npz", allow_pickle=True)
    L, k = z["L"], int(z["contact"])
    kend = max(k - 1, 1) if k >= 0 else len(L) - 1
    return dict(t=L[:, 0].tolist(), p=L[:, 7:10].tolist(), n=L[:, 13:16].tolist(), kend=int(kend))


def main():
    import tt_fast
    ap = argparse.ArgumentParser()
    ap.add_argument("seeds")
    ap.add_argument("--shifts", default="-0.1:0.1:0.01")
    ap.add_argument("--out", default="out/tt5/shift.jsonl")
    ap.add_argument("--workers", type=int, default=6)
    a = ap.parse_args()
    cl = classes()
    if a.seeds in ("miss", "touched", "solved"):
        seeds = sorted(s for s, c in cl.items() if c == a.seeds)
    elif a.seeds == "all":
        seeds = sorted(cl)
    else:
        seeds = [int(x) for x in a.seeds.split(",")]
    lo, hi, st = (float(x) for x in a.shifts.split(":"))
    shifts = [round(x, 4) for x in np.arange(lo, hi + st / 2, st)]
    params = tt_fast.read_params(PARAMS)
    ctl = os.path.abspath(CONTROLLER)
    done = set()
    if os.path.exists(a.out):
        for l in open(a.out):
            r = json.loads(l)
            done.add((r["seed"], r["shift"]))
    jobs, keys = [], []
    for sd in seeds:
        tr = traj(sd)
        for sh in shifts:
            if (sd, sh) in done:
                continue
            jobs.append((params, sd, None, ctl, {"orc_traj": dict(tr, shift=sh)}))
            keys.append((sd, sh))
    print(f"{len(seeds)} serves x {len(shifts)} shifts = {len(jobs)} rollouts to run ({len(done)} done)", flush=True)
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    with open(a.out, "a") as f:
        pool = tt_fast.pool(a.workers)
        for (sd, sh), r in zip(keys, pool.imap(tt_fast.episode, jobs, chunksize=1)):
            row = {"seed": sd, "shift": sh, "cls0": cl.get(sd), "error": r.get("error"), "hit": r.get("hit"), "solved": r.get("solved"), "landed": r.get("landed"),
                   "land_xy": r.get("land_xy"), "t_contact": r.get("t_contact"), "ball_out": r.get("ball_out"), "paddle_speed": r.get("paddle_speed")}
            f.write(json.dumps(row) + "\n")
            f.flush()


if __name__ == "__main__":
    main()
