"""Closed-loop sensitivity of a stage's outcomes to its activation offsets, from rec_dither.py traces.

    .venv/bin/python scratchpad/btl3/dither_fit.py out/btl3/dith_s2 2 [ridge]

Outcomes y (per run, where defined): the NEXT stage's trigger state (predicted crossing x, y; vertical speed bv_z), the release velocity,
the arrival (x, y).  Linear model y = a + S d (+ covariates: the stage's ball features and the live arm state at the trigger), ridge,
leave-one-out R^2 from the hat matrix.  Saves S, a, the outcome means and covariance to <dir>/fit.npz.
"""
import glob
import sys

import numpy as np

sys.path.insert(0, "scratchpad/btl3")
import dlib  # noqa: E402

OUT_NAMES = ["nx", "ny", "nbz", "relvx", "relvy", "relvz", "arrx", "arry"]


def load_runs(d, stage):
    rows = []
    for fn in sorted(glob.glob(d + "/live_*.npz")):
        z = np.load(fn)
        r = dlib.stage_run(z, stage)
        if r is None:
            continue
        r["dither"] = np.array(z["dither"]) if "dither" in z.files else np.zeros((16, 6))
        r["seed"] = int(fn.split("_")[-1].split(".")[0])
        rows.append(r)
    return rows


def outcomes(r):
    n = r["next"]
    y = [n["pc"][0] if n else np.nan, n["pc"][1] if n else np.nan, n["bv"][2] if n else np.nan,
         r["rel_v"][0], r["rel_v"][1], r["rel_v"][2],
         r["arr"][0] if r["arr"] is not None else np.nan, r["arr"][1] if r["arr"] is not None else np.nan]
    return np.array(y)


def cov_features(r):
    return np.concatenate([[r["pc"][0], r["pc"][1]], r["live"][0]])


def ridge_loo(X, y, lam):
    n = len(y)
    mu, sd = X.mean(0), X.std(0) + 1e-9
    Z = (X - mu) / sd
    A = np.column_stack([np.ones(n), Z])
    R = lam * np.eye(A.shape[1]); R[0, 0] = 0
    M = np.linalg.solve(A.T @ A + R, A.T)
    Hm = A @ M
    e = y - Hm @ y
    loo = e / (1 - np.diag(Hm))
    return 1 - np.sum(loo ** 2) / np.sum((y - y.mean()) ** 2), (mu, sd, M @ y)


def main():
    d, stage = sys.argv[1], int(sys.argv[2])
    lam = float(sys.argv[3]) if len(sys.argv) > 3 else 10.0
    rows = load_runs(d, stage)
    Y = np.array([outcomes(r) for r in rows])
    D = np.array([r["dither"].reshape(-1) for r in rows])
    C = np.array([cov_features(r) for r in rows])
    ok = np.array([r["gate"] and not r["body"] for r in rows])
    print(f"stage {stage}: {len(rows)} runs; with a gate crossing and no body hit {ok.sum()}; dither sd {D.std():.3f}")
    print("outcome means / sd over all runs:", {n: (round(float(np.nanmean(Y[:, j])), 3), round(float(np.nanstd(Y[:, j])), 3)) for j, n in enumerate(OUT_NAMES)})
    S = np.full((len(OUT_NAMES), D.shape[1]), np.nan)
    A0 = np.zeros(len(OUT_NAMES))
    for j, name in enumerate(OUT_NAMES):
        m = ok & ~np.isnan(Y[:, j])
        if m.sum() < 30:
            continue
        for label, X in (("dither", D[m]), ("covariates", C[m]), ("dither+cov", np.column_stack([D[m], C[m]]))):
            r2, _ = ridge_loo(X, Y[m, j], lam)
            if label == "dither":
                r2d = r2
            elif label == "covariates":
                r2c = r2
            else:
                r2dc = r2
        # S from the joint regression on dither + covariates (the covariates absorb the start-to-start variation)
        X = np.column_stack([D[m], C[m]])
        mu, sd = X.mean(0), X.std(0) + 1e-9
        Z = (X - mu) / sd
        Aa = np.column_stack([np.ones(len(Z)), Z])
        R = lam * np.eye(Aa.shape[1]); R[0, 0] = 0
        coef = np.linalg.solve(Aa.T @ Aa + R, Aa.T @ Y[m, j])
        S[j] = coef[1:1 + D.shape[1]] / sd[:D.shape[1]]
        A0[j] = coef[0] - np.sum(coef[1:] * mu / sd)
        print(f"{name:6s} n {m.sum():3d} LOO R^2: dither {r2d:5.2f} covariates {r2c:5.2f} both {r2dc:5.2f} | |S| per unit offset: rms {np.sqrt(np.mean(S[j] ** 2)):.2f}")
    np.savez(d + "/fit.npz", S=S, A0=A0, Ymean=np.nanmean(Y[ok], 0), Ycov=np.cov(Y[ok & ~np.isnan(Y).any(1)].T) if (ok & ~np.isnan(Y).any(1)).sum() > 10 else 0, names=np.array(OUT_NAMES))
    print("saved", d + "/fit.npz")


if __name__ == "__main__":
    main()
