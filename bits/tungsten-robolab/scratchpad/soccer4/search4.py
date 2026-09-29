"""sep-CMA over a soccer skill's tunables on rotating fresh starts.

    search4.py --init P --out O --only a,b,c [--set k=v,...] --stage bal
               --env myoChallengeSoccerP2-v0 --controller bin/x
               --seed0 82000 --k 6 --gens 15 --pop 12 --workers 3 --seconds 9

Each generation draws k fresh seeds (seed0 + gen * k ...); every candidate of
the generation runs on the same seeds (paired), scored by the task's
practice_score(stage) averaged over them. Writes O (best candidate by its
generation's score), O.mean (the search mean each generation) and O.log.
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


def read_params(path):
    out = {}
    for line in open(path):
        p = line.split()
        if len(p) >= 2 and not line.startswith("#"):
            out[p[0]] = float(p[1])
    return out


def describe(params, env, controller):
    os.environ["MYO_SOCCER_ENV"] = env
    from myo_bridge import MyoSim
    from tasks.myo_soccer import MyoSoccerTask
    p = dict(params)
    p["__describe"] = 1
    sim = MyoSim(MyoSoccerTask(), params=p, controller=controller, seed=1)
    sim.start_controller()
    out = []
    for line in sim.proc.stdout:
        line = line.strip()
        if line == "END":
            break
        if line.startswith("TUNABLE"):
            _, name, d, lo, hi = line.split()
            out.append((name, float(d), float(lo), float(hi)))
    sim.stop_controller()
    seen, uniq = set(), []
    for t in out:
        if t[0] not in seen:
            seen.add(t[0])
            uniq.append(t)
    return uniq


def worker(job):
    params, seed, env, controller, seconds, stage = job
    os.environ["MYO_SOCCER_ENV"] = env
    from myo_bridge import MyoSim
    from tasks.myo_soccer import MyoSoccerTask, practice_score
    try:
        m = MyoSim(MyoSoccerTask(), params=params, controller=controller, seed=seed).run(seconds)
        m.pop("events", None)
        return practice_score(m, stage), m
    except Exception as e:
        return -1e3, {"error": str(e)[:300]}


def write(path, params, header):
    with open(path, "w") as f:
        for h in header:
            f.write("# " + h + "\n")
        for k in sorted(params):
            if not k.startswith("__"):
                f.write(f"{k} {float(params[k])!r}\n")


KEYS = ["plant_err", "walk_closed", "walk_t_arrive", "bal1_s", "bal_l_tot", "bal_r_tot", "bal_s", "bal_l", "bal_r", "stand_time", "goal", "goal_inside", "strike_zone", "strike_medial_m", "ball_speed",
        "n_steps", "ap_best_stand", "ap_err", "yaw_swing_deg", "yaw_touch_deg", "t_touch", "fallen"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--init", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--only", required=True)
    ap.add_argument("--set", default="")
    ap.add_argument("--stage", required=True)
    ap.add_argument("--env", default="myoChallengeSoccerP2-v0")
    ap.add_argument("--controller", required=True)
    ap.add_argument("--seed0", type=int, default=82000)
    ap.add_argument("--k", type=int, default=6)
    ap.add_argument("--fixed_seeds", default="")
    ap.add_argument("--seed_list", default="")
    ap.add_argument("--gens", type=int, default=15)
    ap.add_argument("--pop", type=int, default=12)
    ap.add_argument("--sigma", type=float, default=0.12)
    ap.add_argument("--workers", type=int, default=3)
    ap.add_argument("--seconds", type=float, default=9.0)
    ap.add_argument("--rseed", type=int, default=1)
    ap.add_argument("--note", default="")
    a = ap.parse_args()
    from search import SepCMA

    init = read_params(a.init)
    for kv in a.set.split(","):
        if "=" in kv:
            k, v = kv.split("=")
            init[k.strip()] = float(v)
    ctl = os.path.abspath(a.controller)
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
    log = open(a.out + ".log", "a")
    log.write(json.dumps({"start": time.strftime("%H:%M:%S"), "args": vars(a), "names": names}) + "\n")
    best = -1e18
    t0 = time.time()
    fixed = [int(s) for s in a.fixed_seeds.split(",") if s]
    with mp.Pool(a.workers) as pool:
        for g in range(a.gens):
            pool_ = [int(x) for x in a.seed_list.split(",") if x]
            seeds = fixed or ([pool_[(g * a.k + j) % len(pool_)] for j in range(a.k)] if pool_ else
                              [a.seed0 + g * a.k + j for j in range(a.k)])
            X = es.ask()
            if g == 0:
                X[0] = x0
            jobs = [(to_params(x), sd, a.env, ctl, a.seconds, a.stage) for x in X for sd in seeds]
            res = pool.map(worker, jobs)
            k = len(seeds)
            sc = np.array([np.mean([res[i * k + j][0] for j in range(k)]) for i in range(len(X))])
            es.tell(X, sc)
            i = int(np.argmax(sc))
            mets = [res[i * k + j][1] for j in range(k)]
            summ = {key: round(float(np.mean([float(m.get(key) or 0) for m in mets if not isinstance(m.get(key), str)])), 3)
                    for key in KEYS if any(key in m for m in mets)}
            summ["zones"] = [m.get("strike_zone") for m in mets]
            if g == 0:
                summ0 = {"x0_score": round(float(sc[0]), 3)}
            else:
                summ0 = {}
            if sc[i] > best:
                best = float(sc[i])
                write(a.out, to_params(X[i]), [f"search4 {a.note}: stage {a.stage} gen {g + 1} score {sc[i]:.3f} seeds {seeds}",
                                               json.dumps(summ)])
            write(a.out + ".mean", to_params(es.mean), [f"search4 mean after gen {g + 1} {a.note}"])
            line = {"gen": g + 1, "t": round(time.time() - t0), "best": round(best, 3), "gen_best": round(float(sc[i]), 3),
                    "gen_mean": round(float(np.mean(sc)), 3), "sigma": round(float(es.sigma), 4), **summ0, "summ": summ}
            print(json.dumps(line), flush=True)
            log.write(json.dumps(line) + "\n")
            log.flush()


if __name__ == "__main__":
    main()
