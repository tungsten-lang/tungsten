"""Static steering map for myo_baoding: which hand postures hold the pair at
which angle.

The round-2 skill holds the balls in a trough of the cupped hand along the
palm's long axis (pair angle ~85 deg); the targets only pass over that
resting pair once per turn, so the rotating tasks score ~0.1 and HOLD
targets elsewhere score nothing. If the hand can hold the pair at other
angles, a posture per target angle (the skill's posture map, `fm_*`: per
joint group a second-order Fourier series in the targets' angle phi*) keeps
the pair on the targets over a wider arc.

This samples random constant joint-group offsets over the cup (through
myo_baoding_v3's field with pf_force = 1 and only the constant terms set),
holds each for 3 s, and records the settled pair angle, the pair's centring
and whether both balls stayed. `fit` then bins the held, centred samples by
pair angle, takes each bin's mean offset, and least-squares fits the
posture-map coefficients (c1 s1 c2 s2 per group) so that the map at angle
phi* reproduces the bin's posture, writing a params file for myo_baoding(_v3)
with the map (fm_*) in place and the error synergy off.

    .venv-myo/bin/python playground/tasks/myo_baoding_steer.py sample --params params/myo_baoding_r2.txt --n 400 --out out/steer.json
    .venv-myo/bin/python playground/tasks/myo_baoding_steer.py fit --data out/steer.json --params params/myo_baoding_r2.txt --out params/x.txt
"""

import argparse
import json
import multiprocessing as mp
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
PLAY = os.path.dirname(HERE)
ROOT = os.path.dirname(PLAY)
sys.path.insert(0, PLAY)
sys.path.insert(0, HERE)

GROUPS = ["dev", "flex", "cabd", "cflex", "mp", "ip", "f2", "p2", "f3", "p3", "f4", "p4", "f5", "p5"]
FM = ["deviation", "flexion", "cmc_abduction", "cmc_flexion", "mp_flexion", "ip_flexion",
      "f2", "p2", "f3", "p3", "f4", "p4", "f5", "p5"]


def read_params(path):
    out = {}
    for line in open(path):
        t = line.split()
        if len(t) >= 2 and not line.startswith("#"):
            out[t[0]] = float(t[1])
    return out


def run(job):
    params, dq, seed, controller = job
    from myo_bridge import MyoSim, load_task
    from myo_baoding import cache, palm_frame, local_xy
    task = load_task("myo_baoding")
    task.env_kwargs = {"max_episode_steps": 120}
    p = dict(params)
    p.update({"pf": 1.0, "pf_force": 1.0, "k_rot": 0.0})
    for g in GROUPS:
        for h in "acs":
            p[f"pfp_{g}_{h}"] = 0.0
    for g, v in zip(GROUPS, dq):
        p[f"pfp_{g}_a"] = float(v)
    for k in list(p):
        if k.startswith("fm_"):
            p[k] = 0.0
    sim = MyoSim(task, params=p, seed=seed, controller=controller)
    m = sim.run()
    c = cache(sim)
    P, R = palm_frame(sim, c)
    b1 = local_xy(sim, c, c.balls[0], P, R)
    b2 = local_xy(sim, c, c.balls[1], P, R)
    phi = float(np.arctan2(b1[1] - b2[1], b1[0] - b2[0]))
    mid = float(np.hypot(0.5 * (b1[0] + b2[0]), 0.5 * (b1[1] + b2[1])))
    return {"dq": [float(v) for v in dq], "seed": seed, "phi": phi, "mid": mid,
            "held": float(m["steps"] >= 120), "z": [float(b1[2]), float(b2[2])],
            "r": [float(np.hypot(b1[0], b1[1])), float(np.hypot(b2[0], b2[1]))]}


def cmd_sample(a):
    params = read_params(a.params)
    rng = np.random.default_rng(a.seed)
    jobs = []
    for i in range(a.n):
        dq = rng.uniform(-a.amp, a.amp, len(GROUPS)) if i else np.zeros(len(GROUPS))
        jobs.append((params, dq, a.seed0 + (i % a.seeds), a.controller))
    with mp.get_context("spawn").Pool(a.workers) as pool:
        res = pool.map(run, jobs, chunksize=4)
    json.dump(res, open(a.out, "w"))
    ok = [r for r in res if r["held"] and r["mid"] < 0.01]
    print(f"{len(res)} samples, {len(ok)} held + centred; pair angle range of those "
          f"{np.degrees(min(r['phi'] for r in ok)):.0f} .. {np.degrees(max(r['phi'] for r in ok)):.0f} deg" if ok else "none held")


def cmd_fit(a):
    data = json.load(open(a.data))
    params = read_params(a.params)
    ok = [r for r in data if r["held"] and r["mid"] < a.mid]
    phis = np.array([r["phi"] for r in ok])
    dqs = np.array([r["dq"] for r in ok])
    bins = np.linspace(-np.pi, np.pi, a.bins + 1)
    centres, means = [], []
    for i in range(a.bins):
        sel = (phis >= bins[i]) & (phis < bins[i + 1])
        if sel.sum() >= a.min_count:
            centres.append(0.5 * (bins[i] + bins[i + 1]))
            means.append(dqs[sel].mean(axis=0))
            print(f"bin {np.degrees(centres[-1]):6.0f} deg: {sel.sum():3d} samples")
    centres = np.array(centres)
    means = np.array(means)
    # map(phi*) = c1 cos + s1 sin + c2 cos2 + s2 sin2 (no constant: the cup)
    X = np.stack([np.cos(centres), np.sin(centres), np.cos(2 * centres), np.sin(2 * centres)], axis=1)
    coef, *_ = np.linalg.lstsq(X, means - means.mean(axis=0) * 0.0, rcond=None)
    out = dict(params)
    for gi, g in enumerate(FM):
        for hi, h in enumerate(["c1", "s1", "c2", "s2"]):
            out[f"fm_{g}_{h}"] = float(np.clip(coef[hi, gi], -0.6, 0.6))
    out["k_rot"] = a.k_rot
    with open(a.out, "w") as f:
        f.write(f"# myo_baoding params: posture map fitted to {len(ok)} held, centred static samples "
                f"({len(centres)} angle bins) by myo_baoding_steer.py\n")
        for k in sorted(out):
            f.write(f"{k} {out[k]!r}\n")
    print("wrote", a.out)


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("sample")
    s.add_argument("--params", required=True)
    s.add_argument("--n", type=int, default=400)
    s.add_argument("--amp", type=float, default=0.5)
    s.add_argument("--seeds", type=int, default=4)
    s.add_argument("--seed0", type=int, default=60000)
    s.add_argument("--seed", type=int, default=1)
    s.add_argument("--workers", type=int, default=3)
    s.add_argument("--controller", default=os.path.join(ROOT, "bin", "robolab_myo_baoding_v3"))
    s.add_argument("--out", required=True)
    f = sub.add_parser("fit")
    f.add_argument("--data", required=True)
    f.add_argument("--params", required=True)
    f.add_argument("--bins", type=int, default=12)
    f.add_argument("--min-count", type=int, default=3)
    f.add_argument("--mid", type=float, default=0.01)
    f.add_argument("--k-rot", type=float, default=0.0)
    f.add_argument("--out", required=True)
    a = ap.parse_args()
    {"sample": cmd_sample, "fit": cmd_fit}[a.cmd](a)


if __name__ == "__main__":
    main()
