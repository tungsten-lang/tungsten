#!/usr/bin/env python3
"""Stage 1, second half: T3's ideal pad-space arm servo (o5a) with the champion's grip and with firmer grips, serves 98000-98099. Read-only.

    .venv-myo/bin/python scratchpad/tt4/o5_table.py

Per variant: solved and hit serves of 100, serves on which the paddle was EVER more than 0.5 m from the palm (T3's `palm_err_max` criterion; NOT a grip failure: in every run it happens after the impact or on serves that never touched the ball, never before contact, see PLANE_NOTE.md), and the pad's error against the plan at the servo's last
tick (`o5_pad_err_last` = position error xyz in m, then orientation error in degrees), median over the serves that have it.
"""
import json
import os

import numpy as np

R = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
VARIANTS = [("T3's o5a, champion grip (recorded)", "out/tt3/o5a_A.jsonl"), ("o5a, champion grip (re-run here)", "out/tt4/o5_base_A.jsonl"),
            ("o5a, grip_drive 1.5", "out/tt4/o5_gd15_A.jsonl"), ("o5a, gfull (firmest working grip)", "out/tt4/o5_gfull_A.jsonl")]


def main():
    print(f"{'variant':38s} {'rows':>4s} {'hit':>4s} {'solved':>6s} {'palm>0.5m ever':>14s} | {'pad pos err cm':>14s} {'pad ori err deg':>15s}")
    for label, path in VARIANTS:
        p = os.path.join(R, path)
        if not os.path.exists(p):
            print(f"{label:38s} (not run yet)")
            continue
        rows = [json.loads(l) for l in open(p)]
        rows = [r for r in rows if 98000 <= r.get("seed", 0) < 98100]
        hit = sum(1 for r in rows if r.get("hit", 0) > 0)
        solved = sum(1 for r in rows if r.get("solved", 0) > 0)
        lost = sum(1 for r in rows if r.get("palm_err_max", 0) > 0.5)
        pe = [r["o5_pad_err_last"] for r in rows if r.get("o5_pad_err_last")]
        pos = [100 * float(np.linalg.norm(e[:3])) for e in pe]
        ori = [e[3] for e in pe]
        print(f"{label:38s} {len(rows):4d} {hit:4d} {solved:6d} {lost:14d} | {np.median(pos):14.1f} {np.median(ori):15.1f}")


if __name__ == "__main__":
    main()
