#!/usr/bin/env python3
"""Plane-hold comparison of table-tennis controllers from their per-episode records (TT_SAVE_LOG npz + the tt_eval rows). Read-only.

    .venv-myo/bin/python scratchpad/tt4/compare_plane.py

For each dataset and side: serves, hits, solved, how far the pad normal turns in the last 50 / 100 / 200 ms before contact (median deg), its turning rate at
contact (median deg/s), and the face's error against the aim normal over 0.3-0.5 s (the task's own `normal_err_deg`, median). Sides come from the rows'
`side` code; which code is the forehand is read off the ball's lateral position at contact (forehand = the side whose hits cross at y > 0.08 m).
"""
import json
import os

import numpy as np

R = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DATASETS = [
    ("champion c3 (set A)", "out/tt3/o0_A.jsonl", "out/tt3/logs_o0", range(98000, 98100)),
    ("r9 live tracking, forehand-practised", "out/tt4/lt_fh.jsonl", "out/tt4/logs_lt_fh", range(98000, 98100)),
    ("r9 live tracking, backhand-practised", "out/tt4/lt_bh.jsonl", "out/tt4/logs_lt_bh", range(98000, 98100)),
]


def ang(a, b):
    return float(np.degrees(np.arccos(np.clip(a @ b / (np.linalg.norm(a) * np.linalg.norm(b)), -1, 1))))


def main():
    print(f"{'dataset':40s} {'side':9s} {'serves':>6s} {'hit':>4s} {'solved':>6s} | {'rot 50ms':>8s} {'100ms':>6s} {'200ms':>6s} | {'rate@contact':>12s} | {'face err vs aim':>15s}")
    for label, rows_path, logdir, seeds in DATASETS:
        rows = {}
        for line in open(os.path.join(R, rows_path)):
            r = json.loads(line)
            if r.get("seed") in seeds:
                rows[r["seed"]] = r
        # which side code is the forehand: the code whose hits cross at y > 0.08
        ycode = {}
        recs = {}
        for seed, r in rows.items():
            f = os.path.join(R, logdir, f"{seed}.npz")
            if not os.path.exists(f):
                continue
            z = np.load(f, allow_pickle=True)
            k = int(z["contact"])
            if k >= 3:
                recs[seed] = (z["L"], k - 1)
                ycode.setdefault(r["side"], []).append(z["L"][k - 1, 2])
        fore_code = max(ycode, key=lambda c: np.mean(ycode[c])) if ycode else None
        for name, code_sel in (("forehand", lambda c: c == fore_code), ("backhand", lambda c: c != fore_code and c in ycode)):
            sel = [s for s, r in rows.items() if code_sel(r["side"])]
            hits = [s for s in sel if s in recs]
            solved = sum(1 for s in sel if rows[s].get("solved", 0) > 0)
            rot = {0.05: [], 0.10: [], 0.20: []}
            rate = []
            for s in hits:
                L, kk = recs[s]
                t = L[:, 0]
                for lag in rot:
                    j = int(np.argmin(np.abs(t - (t[kk] - lag))))
                    rot[lag].append(ang(L[kk, 13:16], L[j, 13:16]))
                k0 = max(kk - 2, 0)
                rate.append(ang(L[kk, 13:16], L[k0, 13:16]) / max(t[kk] - t[k0], 1e-6))
            ferr = [rows[s]["normal_err_deg"] for s in sel if "normal_err_deg" in rows[s]]
            med = lambda x: float(np.median(x)) if len(x) else float("nan")
            print(f"{label:40s} {name:9s} {len(sel):6d} {len(hits):4d} {solved:6d} | {med(rot[0.05]):8.1f} {med(rot[0.10]):6.1f} {med(rot[0.20]):6.1f} | {med(rate):12.0f} | {med(ferr):15.1f}")


if __name__ == "__main__":
    main()
