"""Pen-gap statistics of a set of captured penultimate-touchdown states <prefix>_s<seed>: per state the gap (board - pen toe), plant side, COM speed,
torso pitch; summary: how many states, how many without a plant flight, gap mean / sd / within +-tol of a target.
usage: gapscan2.py <prefix> <first_seed> <last_seed> [target_gap] [tol] [--quiet]"""
import os, sys, json
os.environ.setdefault("MUJOCO_GL", "cgl")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
import numpy as np
import long_jump_limits as L
import long_jump_mine as M


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    quiet = "--quiet" in sys.argv
    prefix, a, b = args[0], int(args[1]), int(args[2])
    target = float(args[3]) if len(args) > 3 else 2.83
    tol = float(args[4]) if len(args) > 4 else 0.15
    body = None
    rows = []
    miss = []
    for sd in range(a, b + 1):
        name = f"{prefix}_s{sd}"
        p = os.path.join(L.OUT, f"{name}_capture.npz")
        if not os.path.exists(p):
            miss.append(sd)
            continue
        cap = L.load_capture(name)
        if body is None:
            body = L.Body(cap["task"], cap["board_x"], json.loads(cap["env"]))
        f = M.features(body, cap)
        rows.append((sd, cap["plant"], f["gap"], f["vx"], f["torso"], f["com_z"], f["swing_ahead"]))
        if not quiet:
            print("s%-5d plant %s gap %.3f vx %.2f torso %+.2f z %.3f swing_ahead %+.2f" % rows[-1])
    g = np.array([r[2] for r in rows])
    print("SUMMARY %s seeds %d-%d: %d captured, %d without a plant flight %s; gap mean %.3f sd %.3f min %.2f max %.2f; within %.2f of %.2f: %d (%.0f%%); plant sides l/r: %d/%d" % (
        prefix, a, b, len(rows), len(miss), miss[:12], g.mean(), g.std(), g.min(), g.max(), tol, target,
        int((np.abs(g - target) <= tol).sum()), 100.0 * (np.abs(g - target) <= tol).mean(),
        sum(1 for r in rows if r[1] == "l"), sum(1 for r in rows if r[1] == "r")))


main()
