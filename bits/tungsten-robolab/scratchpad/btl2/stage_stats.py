"""Closed-loop per-stage statistics on unseen starts (the analog of the fit's 'good'):

    OMP_NUM_THREADS=1 .venv/bin/python scratchpad/btl2/stage_stats.py ctl params s0 s1 secs [workers]

For pass index k (0 the launch, 1 the left hand's return, 2 the right hand's, ...): how many starts reached it, how many crossed the gate
without a body hit, the bounce's distance to the gate, the rise apex, the arrival at the receiving hand (mean and sd) and the share whose
arrival is within 0.14 m of the stage's target; then the task's own streaks.
"""
import sys
from collections import defaultdict
from multiprocessing import Pool

import numpy as np

sys.path.insert(0, "scratchpad/btl2")
from common import load, run_seed  # noqa: E402

TARGETS = {0: (-0.12, 0.36), 1: (0.50, -0.26), 2: (-0.12, 0.36)}   # pass k's intended arrival at the receiving hand (k >= 3 alternate)


def main():
    ctl, pfile, s0, s1, secs = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), float(sys.argv[5])
    workers = int(sys.argv[6]) if len(sys.argv) > 6 else 2
    params = load(pfile)
    with Pool(workers) as p:
        res = p.map(run_seed, [(ctl, params, s, secs) for s in range(s0, s1)])
    st = defaultdict(lambda: defaultdict(list))
    for r in res:
        for k, e in enumerate(r["pass_log"]):
            if not e["released"]:
                continue
            d = st[k]
            d["n"].append(1)
            d["gate"].append(1 if e["gate"] else 0)
            d["body0"].append(1 if e["body"] == 0 else 0)
            if e["bounce_gd"] is not None:
                d["bgd"].append(e["bounce_gd"])
            if e["rise_apex"]:
                d["apex"].append(e["rise_apex"])
            if e["arrive_xy"] is not None:
                d["arr"].append(e["arrive_xy"])
                t = np.array(TARGETS[min(k, 2) if k < 3 else (1 if k % 2 == 1 else 2)])
                d["near"].append(1 if float(np.hypot(*(np.array(e["arrive_xy"]) - t))) < 0.14 else 0)
            d["ok"].append(1 if e["ok"] else 0)
    for k in sorted(st):
        d = st[k]
        arr = np.array(d["arr"]) if d["arr"] else np.zeros((1, 2))
        print(f"pass {k}: n {len(d['n'])} gate {sum(d['gate'])} body0 {sum(d['body0'])} ok(task) {sum(d['ok'])} | bgd {np.mean(d['bgd']) if d['bgd'] else 0:.3f} "
              f"apex {np.mean(d['apex']) if d['apex'] else 0:.2f} | arrival mean ({arr[:,0].mean():+.3f},{arr[:,1].mean():+.3f}) sd ({arr[:,0].std():.3f},{arr[:,1].std():.3f}) "
              f"near {sum(d['near'])}/{len(d['near'])}")
    sk = [r["btl_streak"] for r in res]
    print("streaks", sorted(sk, reverse=True), "mean", round(float(np.mean(sk)), 3), "max", max(sk), ">=2:", sum(1 for s in sk if s >= 2), ">=3:", sum(1 for s in sk if s >= 3))


if __name__ == "__main__":
    main()
