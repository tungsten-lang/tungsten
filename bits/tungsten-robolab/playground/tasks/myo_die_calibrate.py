"""Measure what each myo_die_v3 primitive does to the die.

Runs the skill with `force` = k (after the cup, primitive k once, then the
cup again) on several seeds and records the die's orientation in the palm
frame each step; the rotation over the primitive's chunk,
Q = A_end A_start^T (A = palm^T die), is its effect as a rotation vector in
the palm frame. Prints per primitive the mean effect, its spread and how
often the die stayed in the hand, and with --out writes the `e_<name>_x/y/z`
params (appended to a copy of --params) for the greedy chooser.

    .venv-myo/bin/python playground/tasks/myo_die_calibrate.py --params p.txt --n 12 --out params/x.txt
"""

import argparse
import multiprocessing as mp
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
PLAY = os.path.dirname(HERE)
ROOT = os.path.dirname(PLAY)
sys.path.insert(0, PLAY)
sys.path.insert(0, HERE)

PRIMS = ["flip_xp", "flip_xn", "flip_yp", "flip_yn", "flip_zp", "flip_zn", "tilt_xp", "tilt_xn", "tilt_yp", "tilt_yn"]


def rotvec(R):
    c = np.clip((np.trace(R) - 1) / 2, -1.0, 1.0)
    ang = np.arccos(c)
    if ang < 1e-9:
        return np.zeros(3)
    if ang > np.pi - 1e-6:
        return np.sqrt(np.maximum(0, (np.diag(R) + 1) / 2)) * ang
    w = np.array([R[2, 1] - R[1, 2], R[0, 2] - R[2, 0], R[1, 0] - R[0, 1]]) / (2 * np.sin(ang))
    return w * ang


def run(job):
    params, k, seed, controller = job
    from myo_bridge import MyoSim, load_task
    from myo_die import cache
    task = load_task("myo_die")
    rows = []
    orig = task.on_step

    def on_step(sim, obs, r, info):
        orig(sim, obs, r, info)
        c = cache(sim)
        P = sim.d.xmat[c.frame].reshape(3, 3)
        Ro = sim.d.site_xmat[c.obj_sid].reshape(3, 3)
        rows.append((sim.label, P.T @ Ro))
    task.on_step = on_step
    p = dict(params)
    p["force"] = float(k)
    sim = MyoSim(task, params=p, seed=seed, controller=controller)
    m = sim.run()
    idx = [i for i, (lab, _) in enumerate(rows) if PRIMS[k] in lab]
    if not idx:
        return None
    a0 = rows[max(0, idx[0] - 1)][1]
    a1 = rows[idx[-1]][1]
    return {"w": rotvec(a1 @ a0.T), "held": m.get("held", 0.0), "steps": len(idx)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--params")
    ap.add_argument("--n", type=int, default=12)
    ap.add_argument("--seed0", type=int, default=30000)
    ap.add_argument("--prims", default="0,1,2,3,4,5,6,7,8,9")
    ap.add_argument("--workers", type=int, default=3)
    ap.add_argument("--controller", default=os.path.join(ROOT, "bin", "robolab_myo_die_v3"))
    ap.add_argument("--out")
    a = ap.parse_args()
    params = {}
    if a.params:
        for line in open(a.params):
            t = line.split()
            if len(t) >= 2 and not line.startswith("#"):
                params[t[0]] = float(t[1])
    ks = [int(x) for x in a.prims.split(",")]
    jobs = [(params, k, a.seed0 + s, a.controller) for k in ks for s in range(a.n)]
    with mp.get_context("spawn").Pool(a.workers) as pool:
        res = pool.map(run, jobs)
    eff = {}
    for k in ks:
        rs = [r for (p, kk, s, c), r in zip(jobs, res) if kk == k and r is not None]
        if not rs:
            print(f"{PRIMS[k]:8s} never ran")
            continue
        W = np.array([r["w"] for r in rs])
        mean = W.mean(axis=0)
        spread = float(np.mean(np.linalg.norm(W - mean, axis=1)))
        held = float(np.mean([r["held"] for r in rs]))
        eff[k] = mean
        print(f"{PRIMS[k]:8s} effect {np.round(mean, 2)} |{np.linalg.norm(mean):.2f}| rad, spread {spread:.2f}, "
              f"held {held:.2f}, steps {np.mean([r['steps'] for r in rs]):.0f}")
    if a.out:
        with open(a.out, "w") as f:
            f.write(f"# myo_die_v3 params with primitive effects measured by myo_die_calibrate.py ({a.n} seeds)\n")
            for k, v in sorted(params.items()):
                if not k.startswith("e_"):
                    f.write(f"{k} {v!r}\n")
            for k, w in eff.items():
                for ax, v in zip("xyz", w):
                    f.write(f"e_{PRIMS[k]}_{ax} {float(v)!r}\n")
        print("wrote", a.out)


if __name__ == "__main__":
    main()
