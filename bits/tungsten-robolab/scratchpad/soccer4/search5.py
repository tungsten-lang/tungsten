"""sep-CMA over a soccer skill's tunables with hard-seed mixing, resumable state and a hold-or-fall score.

    search5.py --init P --out O --only a,b,c [--set k=v,...] --controller C --seconds 12
               --k_rand 12 --k_hard 8 --rand_lo 90000 --rand_hi 90400 --hard 90003,90017,... --gens 20 --pop 10 --workers 4

Each generation every candidate runs on the same seeds: k_hard drawn from the hard list and k_rand from the random range
(both rotating deterministically with the generation), scored by hold_score (a completed hold of >= seconds-3 s earns a
bonus, so the score is mostly the pass fraction; bal300's shaping terms otherwise). Writes O (best candidate by its
generation's score), O.mean (search mean), O.log, and O.state.npz (resume with --resume).
"""
import argparse
import json
import math
import multiprocessing as mp
import os
import sys
import time

import numpy as np

HERE = "/Users/erik/tungsten/bits/tungsten-robolab/playground"
sys.path.insert(0, HERE)
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/soccer4")
from search4 import read_params, describe, write  # noqa: E402


def hold_score(m, seconds):
    if m.get("error"):
        return -1e3
    b = float(m.get("bal1_s") or 0.0)
    st = float(m.get("stand_time") or 0.0)
    s = 1.0 * min(b, seconds) + 0.5 * min(st, seconds)
    if b >= seconds - 3.0 and not m.get("fallen"):
        s += 6.0
    return s


def worker(job):
    params, seed, env, controller, seconds, maxt = job
    os.environ["MYO_SOCCER_ENV"] = env
    os.environ["MYO_SOCCER_MAX_TIME"] = maxt
    from myo_bridge import MyoSim
    from tasks.myo_soccer import MyoSoccerTask
    try:
        m = MyoSim(MyoSoccerTask(), params=params, controller=controller, seed=seed).run(seconds)
        m.pop("events", None)
        return hold_score(m, seconds), {k: m.get(k) for k in ("bal1_s", "stand_time", "fallen")}
    except Exception as e:
        return -1e3, {"error": str(e)[:300]}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--init", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--only", required=True)
    ap.add_argument("--set", default="")
    ap.add_argument("--env", default="myoChallengeSoccerP2-v0")
    ap.add_argument("--controller", required=True)
    ap.add_argument("--seconds", type=float, default=12.0)
    ap.add_argument("--k_rand", type=int, default=12)
    ap.add_argument("--k_hard", type=int, default=8)
    ap.add_argument("--rand_lo", type=int, default=90000)
    ap.add_argument("--rand_hi", type=int, default=90400)
    ap.add_argument("--hard", default="")
    ap.add_argument("--gens", type=int, default=20)
    ap.add_argument("--pop", type=int, default=10)
    ap.add_argument("--sigma", type=float, default=0.1)
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--rseed", type=int, default=1)
    ap.add_argument("--resume", action="store_true")
    ap.add_argument("--note", default="")
    a = ap.parse_args()
    from search import SepCMA

    init = read_params(a.init)
    for kv in a.set.split(","):
        if "=" in kv:
            k, v = kv.split("=")
            init[k.strip()] = float(v)
    ctl = os.path.abspath(a.controller)
    os.environ["MYO_SOCCER_MAX_TIME"] = "310"
    tun = {t[0]: t for t in describe(init, a.env, ctl)}
    names = [n for n in a.only.split(",") if n]
    missing = [n for n in names if n not in tun]
    if missing:
        raise SystemExit(f"not declared: {missing}")
    lo = np.array([tun[n][2] for n in names])
    hi = np.array([tun[n][3] for n in names])
    x0 = np.array([(init.get(n, tun[n][1]) - tun[n][2]) / (tun[n][3] - tun[n][2]) for n in names]).clip(0, 1)

    def to_params(x):
        p = dict(init)
        p.update({n: float(l + (h - l) * v) for n, l, h, v in zip(names, lo, hi, np.clip(x, 0, 1))})
        return p

    es = SepCMA(x0, sigma0=a.sigma, seed=a.rseed, popsize=a.pop)
    hard = [int(s) for s in a.hard.split(",") if s]
    state_path = a.out + ".state.npz"
    g0 = 0
    best = -1e18
    if a.resume and os.path.exists(state_path):
        z = np.load(state_path)
        es.mean, es.sigma, es.C, es.pc, es.ps, es.gen = z["mean"], float(z["sigma"]), z["C"], z["pc"], z["ps"], int(z["gen"])
        g0 = int(z["g"])
        best = float(z["best"])
        print(f"resumed at generation {g0}, best {best:.3f}", flush=True)
    log = open(a.out + ".log", "a")
    log.write(json.dumps({"start": time.strftime("%H:%M:%S"), "args": vars(a), "names": names, "resume": a.resume}) + "\n")
    t0 = time.time()
    maxt = "310"
    with mp.Pool(a.workers) as pool:
        for g in range(g0, a.gens):
            rng = np.random.RandomState(1000 + g)
            seeds = list(rng.choice(np.arange(a.rand_lo, a.rand_hi), size=a.k_rand, replace=False))
            if hard and a.k_hard > 0:
                seeds += list(rng.choice(hard, size=min(a.k_hard, len(hard)), replace=False))
            seeds = [int(s) for s in seeds]
            X = es.ask()
            if g == 0:
                X[0] = x0
            jobs = [(to_params(x), sd, a.env, ctl, a.seconds, maxt) for x in X for sd in seeds]
            res = pool.map(worker, jobs)
            k = len(seeds)
            sc = np.array([np.mean([res[i * k + j][0] for j in range(k)]) for i in range(len(X))])
            fails = [sum(1 for j in range(k) if res[i * k + j][1].get("fallen") or (res[i * k + j][1].get("bal1_s") or 0) < a.seconds - 3.0) for i in range(len(X))]
            es.tell(X, sc)
            i = int(np.argmax(sc))
            if sc[i] > best:
                best = float(sc[i])
                write(a.out, to_params(X[i]), [f"search5 {a.note}: gen {g + 1} score {sc[i]:.3f} fails {fails[i]}/{k} seeds {seeds}"])
            write(a.out + ".mean", to_params(es.mean), [f"search5 mean after gen {g + 1} {a.note}"])
            np.savez(state_path, mean=es.mean, sigma=es.sigma, C=es.C, pc=es.pc, ps=es.ps, gen=es.gen, g=g + 1, best=best)
            line = {"gen": g + 1, "t": round(time.time() - t0), "best": round(best, 3), "gen_best": round(float(sc[i]), 3),
                    "gen_mean": round(float(np.mean(sc)), 3), "x0_score": round(float(sc[0]), 3) if g == 0 else None,
                    "fails_best": f"{fails[i]}/{k}", "fails_mean": round(float(np.mean(fails)), 2), "fails_x0": f"{fails[0]}/{k}" if g == 0 else None,
                    "sigma": round(float(es.sigma), 4)}
            print(json.dumps(line), flush=True)
            log.write(json.dumps(line) + "\n")
            log.flush()


if __name__ == "__main__":
    main()
