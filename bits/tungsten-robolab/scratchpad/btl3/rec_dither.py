"""Closed-loop excitation of one stage: random additive activation offsets (pg_dt / pgdt tables) on a stage's 16 arm muscles,
6 knots 50 ms apart from the trigger, N(0, sigma^2) clipped at 2.5 sigma, per start; live traces as rec_live.py plus the offsets.

    OMP_NUM_THREADS=1 .venv/bin/python scratchpad/btl3/rec_dither.py ctl params s0 s1 secs out_dir stage sigma [workers]

`stage` is the program ordinal (0 launch, 1 left return, 2 right return).  The offsets of start `seed` are reproducible
(default_rng(seed * 1000 + stage)) and saved as `dither` (16, 6) in live_<seed>.npz.
"""
import json
import os
import sys

import numpy as np

sys.path.insert(0, "scratchpad/btl3")
sys.path.insert(0, "scratchpad/btl2")

NK = 6


def dither_for(seed, stage, sigma):
    rng = np.random.default_rng(seed * 1000 + stage)
    return np.clip(rng.normal(0.0, sigma, (16, NK)), -2.5 * sigma, 2.5 * sigma)


def job(a):
    ctl, pfile, seed, secs, out_dir, stage, sigma = a
    from common import load
    import rec_live
    fn = os.path.join(out_dir, f"live_{seed}.npz")
    if os.path.exists(fn):
        return seed
    params = load(pfile)
    d = dither_for(seed, stage, sigma)
    params["pg_dt"] = 1.0
    for m in range(16):
        for j in range(NK):
            params[f"pgdt{stage}_{m}_{j}"] = float(d[m, j])
    out, met = rec_live.run_live(seed, params, ctl, secs)
    np.savez_compressed(fn, pass_log=np.array(json.dumps(met.get("pass_log", []))), streak=met.get("btl_streak", -1), dither=d, stage=stage, **out)
    return seed


def main():
    from multiprocessing import Pool
    ctl, pfile, s0, s1, secs, out_dir, stage, sigma = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), float(sys.argv[5]), sys.argv[6], int(sys.argv[7]), float(sys.argv[8])
    workers = int(sys.argv[9]) if len(sys.argv) > 9 else 4
    os.makedirs(out_dir, exist_ok=True)
    with Pool(workers) as p:
        for s in p.imap_unordered(job, [(ctl, pfile, s, secs, out_dir, stage, sigma) for s in range(s0, s1)]):
            print("done", s, flush=True)


if __name__ == "__main__":
    main()
