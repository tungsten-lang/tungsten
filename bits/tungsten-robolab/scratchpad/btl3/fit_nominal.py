"""Nominal contraction trajectories of the programmed strokes, for a tracking servo around the table (round 3).

    .venv/bin/python scratchpad/btl3/fit_nominal.py out/btl3/live_train base_params.txt out_params.txt [ridge]

From closed-loop traces of the champion (rec_live.py) it regresses, per stage p (0 right launch pass, 1 left return, 2 right return), the
stroking hand's 16 muscle contractions at every table knot (17 knots, 25 ms apart from the trigger, the values the controller sees)
on the stage's own schedule features (the predicted crossing offsets ux, uy and the posture features z_i, exactly as the skill forms
them at the trigger):  c_m(t_j) = N0 + ux Nx + uy Ny + sum_i z_i Nz_i.  Writes base_params + pgn<p>_<m>_<j> (N0), pgnx / pgny
(<p>_<m>_<j>) and pgnz<p>_<i>_<m>_<j>, plus pgzn0_i / pgzs0_i for stage 0 (the champion's stage 0 has no posture gains: neutral).
"""
import glob
import sys

import numpy as np

sys.path.insert(0, "scratchpad/btl3")
sys.path.insert(0, "scratchpad/btl2")
import m1_analyze as A  # noqa: E402
from common import load, write_params  # noqa: E402

NK = 17


def clip(v, lim=2.5):
    return float(np.clip(v, -lim, lim))


def stage_data(files, P, zn0=None):
    """rows per stage: dict with feats (ux, uy, z0..z2 raw q) and C (16, NK)."""
    rows = {0: [], 1: [], 2: []}
    nz = int(P.get("pg_nz", 3))
    for fn in files:
        z = np.load(fn)
        for si, (side, k0) in enumerate(A.stage_windows(z)):
            if k0 + 5 * (NK - 1) >= len(z["t"]):
                continue
            pc = A.predicted_cross(z["ball"][k0 - 1], z["ballv"][k0 - 1])
            if pc is None:
                continue
            c = z["c_" + side]
            zq = []
            for i in range(nz):
                j = int(P.get(f"pgzj{i}", 4))
                zq.append(c[k0][2 * j] - c[k0][2 * j + 1])
            C = np.array([c[k0 + 5 * jj] for jj in range(NK)]).T      # (16, NK)
            rows[si].append({"pc": pc, "zq": np.array(zq), "C": C, "seed": fn})
    return rows


def main():
    d, basep, outp = sys.argv[1], sys.argv[2], sys.argv[3]
    ridge = float(sys.argv[4]) if len(sys.argv) > 4 else 3.0
    gamma = float(sys.argv[5]) if len(sys.argv) > 5 else 0.0     # servo weight per muscle ~ (median residual sd / its residual sd)^gamma (pgmw<p>_<m>)
    P = load(basep)
    nz = int(P.get("pg_nz", 3))
    files = sorted(glob.glob(d + "/live_*.npz"))
    rows = stage_data(files, P)
    out = dict(P)
    for si in (0, 1, 2):
        R = rows[si]
        zq = np.array([r["zq"] for r in R])
        if f"pgzn{si}_0" not in P:
            for i in range(nz):
                out[f"pgzn{si}_{i}"] = float(zq[:, i].mean())
                out[f"pgzs{si}_{i}"] = float(max(zq[:, i].std(), 0.01))
        X = []
        for r in R:
            ux = clip((r["pc"][0] - P[f"pgc{si}x"]) / P[f"pgs{si}x"])
            uy = clip((r["pc"][1] - P[f"pgc{si}y"]) / P[f"pgs{si}y"])
            zs = [clip((r["zq"][i] - out.get(f"pgzn{si}_{i}", 0.0)) / out.get(f"pgzs{si}_{i}", 0.05)) for i in range(nz)]
            X.append([1.0, ux, uy] + zs)
        X = np.array(X)
        Y = np.array([r["C"].reshape(-1) for r in R])             # (n, 16*NK)
        Rg = ridge * np.eye(X.shape[1])
        Rg[0, 0] = 0.0
        B = np.linalg.solve(X.T @ X + Rg, X.T @ Y)                # (1+2+nz, 16*NK)
        res = Y - X @ B
        tot = Y.var(0)
        r2 = 1 - res.var(0) / np.maximum(tot, 1e-12)
        print(f"stage {si}: n {len(R)}; contraction sd over starts per knot (mean over muscles) "
              f"{np.round(np.sqrt(tot.reshape(16, NK)).mean(0)[::4], 3).tolist()}; residual sd {np.round(np.sqrt(res.var(0).reshape(16, NK)).mean(0)[::4], 3).tolist()}; "
              f"mean R^2 {np.round(r2.reshape(16, NK).mean(0)[::4], 2).tolist()}")
        B = B.reshape(X.shape[1], 16, NK)
        if gamma > 0:
            sd_m = np.sqrt(res.reshape(len(R), 16, NK).var(0).mean(1))
            w = np.clip((np.median(sd_m) / np.maximum(sd_m, 1e-6)) ** gamma, 0.25, 4.0)
            w = w / w.mean()
            for m in range(16):
                out[f"pgmw{si}_{m}"] = float(w[m])
            print(f"  stage {si} muscle residual sd {np.round(sd_m, 3).tolist()} -> weights {np.round(w, 2).tolist()}")
        for m in range(16):
            for k in range(NK):
                out[f"pgn{si}_{m}_{k}"] = float(B[0, m, k])
                out[f"pgnx{si}_{m}_{k}"] = float(B[1, m, k])
                out[f"pgny{si}_{m}_{k}"] = float(B[2, m, k])
                for i in range(nz):
                    out[f"pgnz{si}_{i}_{m}_{k}"] = float(B[3 + i, m, k])
    write_params(outp, out, f"{basep} + nominal contraction tables (fit_nominal.py on {d}, ridge {ridge})")
    print("wrote", outp, len(out), "keys")


if __name__ == "__main__":
    main()
