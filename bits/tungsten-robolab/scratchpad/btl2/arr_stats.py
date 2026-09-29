"""Closed-loop arrival statistics from a record cache: where/how fast the ball rises through z 0.62 on each side.

    OMP_NUM_THREADS=1 .venv/bin/python scratchpad/btl2/arr_stats.py cache_name [t_from]

Prints, for the k-th rising crossing of z 0.62 after t_from (default 1.4 s) the mean and sd of position and velocity, per crossing
index and side (x < 0.1: the left hand's side).
"""
import pickle
import sys

import numpy as np

name = sys.argv[1]
t0 = float(sys.argv[2]) if len(sys.argv) > 2 else 1.4
c = pickle.load(open(f"scratchpad/btl2/runs/{name}.pkl", "rb"))
rows = {}
for k, r in c.items():
    bp, bv = r["ball"], r["ballv"]
    n = 0
    for j in range(int(t0 / 0.005) + 1, len(bp)):
        if bp[j - 1, 2] < 0.62 <= bp[j, 2] and bv[j, 2] > 0:
            f = (0.62 - bp[j - 1, 2]) / (bp[j, 2] - bp[j - 1, 2])
            p = bp[j - 1] + f * (bp[j] - bp[j - 1])
            v = bv[j - 1] + f * (bv[j] - bv[j - 1])
            rows.setdefault(n, []).append((p[0], p[1], v[0], v[1], v[2], j * 0.005))
            n += 1
for n in sorted(rows):
    A = np.array(rows[n])
    side = "left (x<0.1)" if A[:, 0].mean() < 0.1 else "right"
    print(f"crossing {n} ({side}) n {len(A)} pos mean ({A[:,0].mean():+.3f},{A[:,1].mean():+.3f}) sd ({A[:,0].std():.3f},{A[:,1].std():.3f}) "
          f"vel mean ({A[:,2].mean():+.2f},{A[:,3].mean():+.2f},{A[:,4].mean():+.2f}) sd ({A[:,2].std():.2f},{A[:,3].std():.2f},{A[:,4].std():.2f}) t {A[:,5].mean():.2f}")
