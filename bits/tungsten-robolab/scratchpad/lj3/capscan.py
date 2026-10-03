"""Check-mark scan: the approach is a chaotic function of the board position (floating-point differences in the runway box move the
stride by up to a step over 20 s), so scan board values, capture the penultimate-touchdown state of each and print the gap
(board - penultimate toe) and the state's speed. The pen/plant classification comes from the planner (params B1: planner steering off, j_pl_step 3.2).
usage: capscan.py <params> <controller> <first_board> <step> <count> <prefix> [procs]   (L3)"""
import os
import subprocess
import sys
import json
import multiprocessing as mp

ROOT = "/Users/erik/tungsten/bits/tungsten-robolab"


def one(args):
    params, ctl, b, name = args
    env = dict(os.environ, ROBOLAB_CALIB="v4", ROBOLAB_PROFILE="beyond", ROBOLAB_PROFILE_PARTS="strength,speed,tendon,activation",
               ROBOLAB_LJ_APPROACH=repr(b), MUJOCO_GL="cgl")
    p = subprocess.run(["nice", "-n", "10", os.path.join(ROOT, ".venv/bin/python"), os.path.join(ROOT, "playground/long_jump_limits.py"), "capture",
                        "long_jump_v4_beyond", "--params", params, "--controller", ctl, "--name", name, "--from", "pen"],
                       cwd=ROOT, env=env, capture_output=True, text=True)
    return name, b, p.stdout.strip().splitlines()[-1] if p.stdout.strip() else p.stderr[-300:]


def main():
    params, ctl, first, step, count, prefix = sys.argv[1:7]
    procs = int(sys.argv[7]) if len(sys.argv) > 7 else 2
    jobs = [(params, ctl, round(float(first) + i * float(step), 6), f"{prefix}{i}") for i in range(int(count))]
    with mp.Pool(procs) as pool:
        for name, b, line in pool.imap(one, jobs):
            print(name, b, line[:200], flush=True)


if __name__ == "__main__":
    main()
