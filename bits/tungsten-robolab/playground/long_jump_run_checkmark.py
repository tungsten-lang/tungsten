"""Check-mark learning for LongJumpRunSkill: iterative learning control of the
run-up length across attempts.

A real jumper sets the check mark by running the approach again and again
and moving the mark by the distance the take-off foot missed the board by.
This does the same. Each iteration runs the training starts and measures
where the take-off foot's front ended relative to the foul line
(`foul_max_x`, the TR 30.1.1 quantity; > 0 is a foul), then moves the check
mark (the task's `board_x`, start to foul line, set per rollout as a task
attribute) by the gain times the error against a wanted margin:

    delta_k   = gain * (mean(front_k) - want),   want = -(margin + margin_sd * sd(front_k))
    board_x  += delta_k        (a shorter run-up when the foot lands behind)
    j_aim    += delta_k        (the planner's aim point, metres behind the line,
                                moves with it, so the aim stays at the same
                                spot of the runway: the plan is unchanged and
                                only the line comes to the foot)

A jump without a take-off counts as front = +0.3 m. `--key j_aim` instead
moves the aim alone (the line stays; the plant step changes). Writes the best
iteration's params (by mean official distance) and prints the check mark to
put in the task module.

    ROBOLAB_CONTROLLER=bin/challengers/long_jump_run-x .venv/bin/python playground/long_jump_run_checkmark.py \\
        long_jump_run --params p.txt --seeds None,1001-1007 --iters 4 --out params/x.txt
"""

import argparse
import importlib
import json
import multiprocessing as mp
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from search import read_params, rollout  # noqa: E402


def seeds_of(s):
    out = []
    for part in s.split(","):
        if "-" in part:
            lo, hi = part.split("-")
            out += list(range(int(lo), int(hi) + 1))
        else:
            out.append(None if part in ("None", "0") else int(part))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("task")
    ap.add_argument("--params", nargs="+", required=True)
    ap.add_argument("--seeds", default="None,1001-1007")
    ap.add_argument("--iters", type=int, default=4)
    ap.add_argument("--gain", type=float, default=0.9)
    ap.add_argument("--margin", type=float, default=0.05, help="wanted mean distance of the foot's front behind the line (m)")
    ap.add_argument("--margin-sd", type=float, default=2.0)
    ap.add_argument("--key", default="checkmark", choices=["checkmark", "j_aim"])
    ap.add_argument("--workers", type=int, default=3)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    p = {}
    for f in a.params:
        p.update(read_params(f))
    board = float(importlib.import_module(f"tasks.{a.task}").TASK.board_x)
    seeds = seeds_of(a.seeds)
    log, best = [], None
    with mp.Pool(a.workers) as pool:
        for k in range(a.iters + 1):
            attrs = {"board_x": board}
            res = pool.map(rollout, [(a.task, dict(p), s, 0.0, attrs) for s in seeds], chunksize=1)
            fr = np.array([float(m["foul_max_x"]) if m.get("foul_max_x") is not None else 0.3 for _, m, _ in res])
            off = [m.get("official_m", 0.0) or 0.0 for _, m, _ in res]
            row = {"iter": k, "board_x": round(board, 4), "j_aim": round(p.get("j_aim", 0.12), 4),
                   "front_mean": round(float(fr.mean()), 3), "front_sd": round(float(fr.std()), 3),
                   "front_max": round(float(fr.max()), 3), "fouls": int((fr > 0).sum()),
                   "official_mean": round(float(np.mean(off)), 3),
                   "fails": sum(1 for _, m, _ in res if m.get("failed") or m.get("official_m", 0.0) == 0.0)}
            log.append(row)
            print(json.dumps(row), flush=True)
            if best is None or row["official_mean"] > best[0]:
                best = (row["official_mean"], dict(p), board)
            if k == a.iters:
                break
            want = -(a.margin + a.margin_sd * float(fr.std()))
            delta = a.gain * (float(fr.mean()) - want)
            p["j_aim"] = p.get("j_aim", 0.12) + delta
            if a.key == "checkmark":
                board += delta
    os.makedirs(os.path.dirname(a.out) or ".", exist_ok=True)
    with open(a.out, "w") as f:
        f.write(f"# check-mark ILC ({a.key}) on {a.task}, seeds {a.seeds}: best mean official {best[0]:.3f} "
                f"with check mark (board_x) {best[2]:.4f} m\n")
        f.write(f"# log {json.dumps(log)}\n")
        for kk in sorted(best[1]):
            f.write(f"{kk} {float(best[1][kk])!r}\n")
    print("wrote", a.out, "best mean official", best[0], "check mark", round(best[2], 4))


if __name__ == "__main__":
    main()
