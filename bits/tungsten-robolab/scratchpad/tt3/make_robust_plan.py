"""Robust kinematic-paddle plan (agent T3): per serve the nominal (pitch, yaw, retreat d along +x) maximising the Monte Carlo landing probability under the pad's pitch / yaw / velocity noise
(offline model fitted on the kinematic-paddle runs), written as a plan file (noise-free; add the noise with noisy_plan.py).
    .venv-myo/bin/python scratchpad/tt3/make_robust_plan.py OUT.json --sp 11 --sy 3.5 --sv 0.5"""
import argparse, json, os, sys
import numpy as np
HERE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(HERE, "playground")); sys.path.insert(0, os.path.join(HERE, "scratchpad", "tt3"))
import tt_impact as ti
from make_plans import record, orient

ap = argparse.ArgumentParser()
ap.add_argument("out"); ap.add_argument("--sp", type=float, default=0.0); ap.add_argument("--sy", type=float, default=0.0); ap.add_argument("--sv", type=float, default=0.0)
ap.add_argument("--E", type=float, default=1.0335); ap.add_argument("--MU", type=float, default=0.0731); ap.add_argument("--ALPHA", type=float, default=1.0)
ap.add_argument("--K", type=int, default=64); ap.add_argument("--t_on", type=float, default=0.15); ap.add_argument("--t_off", type=float, default=0.15)
a = ap.parse_args()
rows = {}
for s in "AB":
    for l in open(f"out/tt3/o0_{s}.jsonl"):
        r = json.loads(l); rows[r["seed"]] = r
PIT = np.arange(-30.0, 51.0, 2.0); YAW = np.arange(-28.0, 29.0, 2.0); DEL = np.arange(-0.25, 1.51, 0.25)
PG, YG, DG = np.meshgrid(PIT, YAW, DEL, indexing="ij")
rng = np.random.default_rng(3)
Z = rng.standard_normal((a.K, 5))
plans = {}
for sd in sorted(rows):
    d = record(sd, rows[sd])
    P = np.radians(PG[..., None] + a.sp * Z[:, 0]); Y = np.radians(YG[..., None] + a.sy * Z[:, 1])
    n = np.stack([np.cos(P) * np.cos(Y), np.cos(P) * np.sin(Y), np.sin(P) + 0 * Y], axis=-1)
    vp = np.stack([DG[..., None] + a.sv * Z[:, 2], a.sv * Z[:, 3] + 0 * P, a.sv * Z[:, 4] + 0 * P], axis=-1)
    v = ti.impact(d["vb"], a.ALPHA * vp, n, a.E, a.MU)
    pl = ti.landing_ok(d["p"], v).mean(axis=-1)
    # among the best, prefer the plan with the most neighbours also good (smoothed): use the argmax of a 3x3x1 box average to avoid knife-edge optima
    from scipy.ndimage import uniform_filter
    sm = uniform_filter(pl, size=(3, 3, 1), mode="nearest")
    i, j, k = np.unravel_index(int(np.argmax(sm + 0.01 * pl)), pl.shape)
    n_pos = ti.normal_from_angles(np.radians(PIT[i]), np.radians(YAW[j]))
    n_out = -orient(n_pos)
    vpl = np.array([DEL[k], 0.0, 0.0])
    plans[str(sd)] = {"t_hit": d["t_hit"], "P": (d["p"] - 0.04 * n_out).tolist(), "n_out": n_out.tolist(), "v": vpl.tolist(),
                      "t_on": d["t_hit"] - a.t_on, "t_off": d["t_hit"] + a.t_off, "hit1": bool(d["hit"]), "mc": float(pl[i, j, k])}
json.dump(plans, open(a.out, "w"))
print(f"{a.out}: {len(plans)} robust plans, noise pitch {a.sp} yaw {a.sy} velocity {a.sv}; mean MC landing prob {np.mean([p['mc'] for p in plans.values()]):.3f}; mean retreat {np.mean([p['v'][0] for p in plans.values()]):.2f}")
