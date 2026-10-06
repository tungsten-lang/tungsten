"""Feed-forward outcome correction in the replay (round 4): sensitivities of a stage's smooth outcomes to additive offset knots (pg_dt style, 6 knots
50 ms apart, 16 arm muscles), a ridge predictor of the outcome deviation from the 18 trigger features, and the corrected replays on held-out starts.

    .venv/bin/python scratchpad/btl4/ffc1.py STAGE n_train n_sens [workers]
"""
import sys
import time

import numpy as np

sys.path.insert(0, "scratchpad/btl4")
import rlib  # noqa: E402
from multiprocessing import Pool  # noqa: E402

STAGE = int(sys.argv[1])
NTR = int(sys.argv[2])
NSENS = int(sys.argv[3])
WORKERS = int(sys.argv[4]) if len(sys.argv) > 4 else 6
HAND = rlib.STAGES[STAGE][0]
SEEDS = list(range(13001, 13001 + NTR))
DELTA = 0.02
TARGET = {1: (0.50, -0.26), 2: (-0.12, 0.36)}[STAGE]    # where the next hand meets the ball (oracle_search RIGHT_TARGET / LEFT_TARGET)
YN = ["vx", "vy", "vz", "bx", "by"]
NY = len(YN)


def proxy_ok(summ):
    """a stroke the next hand could take: touched, bounced, crossed the gate, no body hit, arrival within 0.14 m of its spot, apex >= 0.58"""
    if not summ.get("bounced"):
        return False
    return bool(summ.get("gate", 0) > 0 and summ.get("body", 9) == 0 and summ.get("apex", 0) >= 0.58
                and float(np.hypot(*(np.array(summ["arrive"]) - np.array(TARGET)))) < 0.14)


def base_job(sd):
    d = rlib.StartData(sd, f"out/btl4/rec/rec_{sd}.pkl")
    if STAGE not in d.ks:
        return sd, None
    out, s0 = d.run_stage(STAGE)
    y, info = rlib.smooth_outcomes(out, HAND)
    f, pt = d.stage_features(STAGE)
    return sd, {"y": y, "f": f, "pt": pt, "ok": proxy_ok(s0), "summ": {k: s0.get(k) for k in ("gate", "body", "apex", "arrive", "touch", "bounced")}}


def sens_job(sd):
    d = rlib.StartData(sd, f"out/btl4/rec/rec_{sd}.pkl")
    if STAGE not in d.ks:
        return sd, None
    out, s0 = d.run_stage(STAGE)
    y0, _ = rlib.smooth_outcomes(out, HAND)
    if y0 is None:
        return sd, None
    S = np.zeros((NY, 16 * rlib.NDT))
    for m in range(16):
        for k in range(rlib.NDT):
            ys = []
            for sg in (-1.0, 1.0):
                tab = np.zeros((16, rlib.NDT))
                tab[m, k] = sg * DELTA
                o, s = d.run_stage(STAGE, tab)
                y, _ = rlib.smooth_outcomes(o, HAND)
                if y is None:
                    break
                ys.append(y[:NY])
            if len(ys) == 2:
                S[:, m * rlib.NDT + k] = (ys[1] - ys[0]) / (2 * DELTA)
    return sd, S


def corr_job(arg):
    sd, tab = arg
    d = rlib.StartData(sd, f"out/btl4/rec/rec_{sd}.pkl")
    out, s1 = d.run_stage(STAGE, tab)
    y, info = rlib.smooth_outcomes(out, HAND)
    return sd, {"y": y, "ok": proxy_ok(s1), "summ": {k: s1.get(k) for k in ("gate", "body", "apex", "arrive", "touch", "bounced")}}


def main():
    t0 = time.time()
    with Pool(WORKERS) as pool:
        base = dict(pool.map(base_job, SEEDS))
        print(f"base replays {len(SEEDS)} in {time.time() - t0:.0f}s", flush=True)
        seeds = [s for s in SEEDS if base[s] is not None and base[s]["y"] is not None]
        print("usable starts", len(seeds), "proxy ok", sum(base[s]["ok"] for s in seeds), flush=True)
        # sensitivities from the first NSENS usable starts
        ss = seeds[:NSENS]
        t1 = time.time()
        Sall = dict(pool.map(sens_job, ss))
        Ss = np.array([S for S in Sall.values() if S is not None])
        print(f"sensitivities from {len(Ss)} starts in {time.time() - t1:.0f}s", flush=True)
        Sm = Ss.mean(0)
        # consistency of the per-start S with their mean (cosine similarity of rows)
        for i, nm in enumerate(YN):
            cs = [float(Ss[j, i] @ Sm[i] / (np.linalg.norm(Ss[j, i]) * np.linalg.norm(Sm[i]) + 1e-12)) for j in range(len(Ss))]
            print(f"  {nm}: mean-S row norm {np.linalg.norm(Sm[i]):.2f}, per-start norm {np.mean([np.linalg.norm(Ss[j, i]) for j in range(len(Ss))]):.2f}, cos(start, mean) median {np.median(cs):.2f}")
        np.save(f"out/btl4/ffc_S_stage{STAGE}.npy", Sm)
        Y = np.array([base[s]["y"][:NY] for s in seeds])
        F = np.array([base[s]["f"] for s in seeds])
        ok = np.array([base[s]["ok"] for s in seeds])
        yt = Y[ok].mean(0)
        sdv = Y.std(0)
        print("outcome mean", np.round(Y.mean(0), 3).tolist(), "sd", np.round(sdv, 3).tolist(), "target (mean of proxy-ok)", np.round(yt, 3).tolist())
        # split: even/odd starts as train/test for the predictor; the correction is evaluated on the odd (test) starts
        tr = np.arange(len(seeds)) % 2 == 0
        te = ~tr
        mu, sgm = F[tr].mean(0), F[tr].std(0) + 1e-9
        Z = (F - mu) / sgm
        from numpy.linalg import solve
        res = {}
        for lam_w in (3.0, 10.0, 30.0):
            A = np.column_stack([np.ones(tr.sum()), Z[tr]])
            R = lam_w * np.eye(A.shape[1]); R[0, 0] = 0
            Wc = solve(A.T @ A + R, A.T @ (Y[tr] - yt))
            pred = np.column_stack([np.ones(te.sum()), Z[te]]) @ Wc
            r2 = 1 - ((Y[te] - yt - pred) ** 2).sum(0) / ((Y[te] - yt - (Y[tr] - yt).mean(0)) ** 2).sum(0)
            res[lam_w] = (Wc, r2)
            print(f"ridge {lam_w:5.1f}: held-out R^2 of the outcome deviation", dict(zip(YN, np.round(r2, 2).tolist())))
        lam_w = 10.0
        Wc, _ = res[lam_w]
        # the correction: da = -S^T (S S^T + mu I)^-1 yhat   (S scaled by the outcome sds so all outcomes weigh the same)
        Ssc = Sm / sdv[:, None]
        for lam in (0.03, 0.1, 0.3):
            mu_ = lam * np.trace(Ssc @ Ssc.T) / NY
            Gm = -Ssc.T @ np.linalg.inv(Ssc @ Ssc.T + mu_ * np.eye(NY)) / sdv[None, :]      # (96, NY): da = Gm @ yhat (physical units)
            for mode in ("predicted", "oracle"):
                jobs = []
                for i, s in enumerate(seeds):
                    if not te[i]:
                        continue
                    if mode == "predicted":
                        yh = np.concatenate([[1.0], Z[i]]) @ Wc
                    else:
                        yh = Y[i] - yt
                    da = np.clip(Gm @ yh, -0.08, 0.08).reshape(16, rlib.NDT)
                    jobs.append((s, da))
                outs = dict(pool.map(corr_job, jobs))
                Y1 = np.array([outs[s]["y"][:NY] if outs[s]["y"] is not None else np.full(NY, np.nan) for s, _ in jobs])
                Y0 = np.array([base[s]["y"][:NY] for s, _ in jobs])
                ok0 = np.array([base[s]["ok"] for s, _ in jobs])
                ok1 = np.array([outs[s]["ok"] for s, _ in jobs])
                nrm = np.mean([np.abs(a).max() for _, a in jobs])
                print(f"lam {lam:4.2f} {mode:9s}: mean max|da| {nrm:.3f} | outcome sd before {np.round(np.nanstd(Y0, 0), 3).tolist()} after {np.round(np.nanstd(Y1, 0), 3).tolist()} | proxy ok {ok0.sum()} -> {ok1.sum()} of {len(jobs)}", flush=True)
    print(f"done in {time.time() - t0:.0f}s")


if __name__ == "__main__":
    main()
