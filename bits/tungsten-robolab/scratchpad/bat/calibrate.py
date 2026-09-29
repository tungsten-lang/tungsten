"""Newton recalibration of the taim aim gains (batting round 2).

    .venv/bin/python scratchpad/bat/calibrate.py --params params/x.txt --controller bin/challengers/bat_r2-t1 \
        --seeds 5000:5048 --iters 2 --out params/x_cal.txt

Each iteration runs the pitches, fits aim_n (cm) = a0 + a_z dz + a_x dx over them (dz, dx: the program blend's location
mismatch, m) and moves the taim gains by the measured unit-gain sensitivities (-59.4 cm/m for taim_z, -52.4 cm/m for taim_x,
scratchpad/bat/an3.py): taim_z += a_z / 59.4, taim_x += a_x / 52.4, taim_z0 += a0 / (59.4 taim_z), all damped by --damp.
Writes the calibrated params (every other value copied) and prints hits, speed, flow and the aim fit per iteration.
"""
import argparse
import json
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "playground"))
import bat_rep  # noqa: E402
from bat_search import blend_mismatch  # noqa: E402

SZ, SX = 59.4, 52.4


def fit(rows):
    ok = [r for r in rows if r["rec"].get("aim_n_cm") is not None]
    pts = np.array([[r["rec"]["target_x"], r["rec"]["target_z"]] for r in ok])
    dz, dx = np.array([blend_mismatch(x, z) for x, z in pts]).T
    an = np.array([r["rec"]["aim_n_cm"] for r in ok])
    A = np.column_stack([np.ones(len(an)), dz, dx])
    coef = np.linalg.lstsq(A, an, rcond=None)[0]
    res = an - A @ coef
    return coef, res, an


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--params", required=True)
    ap.add_argument("--controller", required=True)
    ap.add_argument("--seeds", default="5000:5048")
    ap.add_argument("--iters", type=int, default=2)
    ap.add_argument("--damp", type=float, default=0.9)
    ap.add_argument("--boost", type=float, default=1.0, help="multiplier on the Newton steps (the measured unit-gain sensitivities overstate the "
                    "response when the swing is far from the probes' operating point: a step then removes only 20-40 % of what it should)")
    ap.add_argument("--workers", type=int, default=2)
    ap.add_argument("--seconds", type=float, default=4.3)
    ap.add_argument("--out", required=True)
    ap.add_argument("--header", default="")
    a = ap.parse_args()
    params = bat_rep.read_params(a.params)
    for k, v in (("taim_z", 0.0), ("taim_x", 0.0), ("taim_z0", 0.0), ("taim_x0", 0.0)):
        params.setdefault(k, v)
    seeds = bat_rep.parse_seeds(a.seeds)
    for it in range(a.iters + 1):
        rows = bat_rep.run_many([bat_rep.job(params, a.controller, s, a.seconds) for s in seeds], a.workers)
        sm = bat_rep.summarise(rows)
        coef, res, an = fit(rows)
        print(f"iter {it}: taim_z {params['taim_z']:.3f} taim_x {params['taim_x']:.3f} taim_z0 {params['taim_z0']:+.4f} | "
              f"hits {sm['hits']}/{sm['n']} power {sm['power']:.3f} hit speed {sm['hit_speed']} flow {sm['flow_mean']} max {sm['flow_max']} | "
              f"aim mean {an.mean():+.2f} sd {an.std():.2f} fit a0 {coef[0]:+.2f} az {coef[1]:+.1f} ax {coef[2]:+.1f} resid rms {np.sqrt(np.mean(res ** 2)):.2f} "
              f"misses {sm['misses']}", flush=True)
        if it == a.iters:
            break
        step = a.damp * a.boost
        params["taim_z"] += step * coef[1] / SZ
        params["taim_x"] += step * coef[2] / SX
        params["taim_z0"] += step * coef[0] / (SZ * max(params["taim_z"], 0.5))
    lines = [f"# {a.header or 'recalibrated taim gains'} (scratchpad/bat/calibrate.py on seeds {a.seeds}, source {a.params})"]
    src = [l.rstrip("\n") for l in open(a.params) if not l.startswith("#")]
    seen = set()
    for l in src:
        t = l.split()
        if len(t) >= 2 and t[0] in ("taim_z", "taim_x", "taim_z0", "taim_x0"):
            lines.append(f"{t[0]} {float(params[t[0]])!r}")
            seen.add(t[0])
        elif l.strip():
            lines.append(l)
    for k in ("taim_z", "taim_x", "taim_z0", "taim_x0"):
        if k not in seen and params[k] != 0.0:
            lines.append(f"{k} {float(params[k])!r}")
    open(a.out, "w").write("\n".join(lines) + "\n")
    print("wrote", a.out)


if __name__ == "__main__":
    main()
