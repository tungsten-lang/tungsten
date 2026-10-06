"""Upper bound of a linear feed-forward correction: per-start sensitivities S_i (central differences, delta 0.02) and the oracle correction
da_i = -S_i^T (S_i S_i^T + mu I)^-1 (y_i - y_t), replayed on the same start.   .venv/bin/python scratchpad/btl4/ffc2.py STAGE n"""
import sys
import numpy as np
sys.path.insert(0, "scratchpad/btl4")
import rlib
from multiprocessing import Pool
STAGE = int(sys.argv[1]); N = int(sys.argv[2])
HAND = rlib.STAGES[STAGE][0]
YN = ["vx", "vy", "vz", "bx", "by"]; NY = 5
DELTA = 0.02


def job(sd):
    d = rlib.StartData(sd, f"out/btl4/rec/rec_{sd}.pkl")
    if STAGE not in d.ks:
        return sd, None
    out, s0 = d.run_stage(STAGE)
    y0, _ = rlib.smooth_outcomes(out, HAND)
    if y0 is None:
        return sd, None
    y0 = y0[:NY]
    S = np.zeros((NY, 96))
    for m in range(16):
        for k in range(rlib.NDT):
            ys = []
            for sg in (-1.0, 1.0):
                tab = np.zeros((16, rlib.NDT)); tab[m, k] = sg * DELTA
                o, s = d.run_stage(STAGE, tab)
                y, _ = rlib.smooth_outcomes(o, HAND)
                if y is None:
                    break
                ys.append(y[:NY])
            if len(ys) == 2:
                S[:, m * rlib.NDT + k] = (ys[1] - ys[0]) / (2 * DELTA)
    return sd, (y0, S)


def corr(arg):
    sd, da = arg
    d = rlib.StartData(sd, f"out/btl4/rec/rec_{sd}.pkl")
    out, s1 = d.run_stage(STAGE, da.reshape(16, rlib.NDT))
    y, _ = rlib.smooth_outcomes(out, HAND)
    return sd, None if y is None else y[:NY]


if __name__ == "__main__":
    seeds = list(range(13001, 13001 + N))
    with Pool(6) as pool:
        res = dict(pool.map(job, seeds))
        res = {k: v for k, v in res.items() if v is not None}
        Y0 = np.array([v[0] for v in res.values()])
        yt = np.median(Y0, 0)
        sdv = Y0.std(0)
        print("n", len(res), "sd before", np.round(sdv, 3).tolist())
        for lam in (0.01, 0.03, 0.1, 0.3):
            jobs = []
            for sd, (y0, S) in res.items():
                Ssc = S / sdv[:, None]
                mu = lam * np.trace(Ssc @ Ssc.T) / NY
                G = -Ssc.T @ np.linalg.inv(Ssc @ Ssc.T + mu * np.eye(NY)) / sdv[None, :]
                da = np.clip(G @ (y0 - yt), -0.1, 0.1)
                jobs.append((sd, da))
            outs = dict(pool.map(corr, jobs))
            Y1 = np.array([outs[sd] if outs[sd] is not None else np.full(NY, np.nan) for sd, _ in jobs])
            # predicted by the linear model
            Yp = np.array([res[sd][0] + res[sd][1] @ da for sd, da in jobs])
            print(f"lam {lam:4.2f}: mean max|da| {np.mean([np.abs(a).max() for _, a in jobs]):.3f} | deviation from target sd before {np.round(np.std(Y0 - yt, 0), 3).tolist()} after (replayed) {np.round(np.nanstd(Y1 - yt, 0), 3).tolist()} (linear prediction {np.round(np.std(Yp - yt, 0), 3).tolist()}) rms deviation before {np.round(np.sqrt(((Y0 - yt) ** 2).mean(0)), 3).tolist()} after {np.round(np.sqrt(np.nanmean((Y1 - yt) ** 2, 0)), 3).tolist()}")
