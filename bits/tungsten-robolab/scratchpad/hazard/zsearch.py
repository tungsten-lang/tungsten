"""zsearch: sep-CMA over a soccer skill's tunables with (a) fresh practice starts every generation, (b) a hold score, (c) a penalty on the
swing leg's wrap-tangent EXPOSURE, on the guarded task (myo_soccer_ng, the rollout is bit-identical to the official one until a NaN).

    zsearch.py --init P --out O --only a,b,c [--set k=v,...] --controller C --seconds 12 --k 24 --seed0 97100 --gens 12 --pop 12
               --workers 4 --w_exp 20 --w_wall 0 [--resume] [--note ...]

Each generation draws k fresh seeds (seed0 + gen * k + i); every candidate runs the same seeds (paired) and scores
    mean over the seeds of [ hold_score - w_exp * e2 - w_leg * max(0, legforce - leg_thr) ]
hold_score = min(bal1_s, T) + 0.5 min(stand, T) + 6 if the hold completes (T - 3 s of one-leg time and not fallen), the search5.py score; e2 = the fraction of the watched substeps
(t >= 3 s) in which recfem_r's wrap margin was within 1e-2 of its tangent (0 when the swing knee is parked far from it; 0.3-0.7 for a hoverer). Any margin < 1e-2 also
costs: exposure to the MuJoCo length_circle NaN sliver is proportional to the density of the margin at zero. A candidate that falls scores about -20 relative to a hold.
Writes O (the generation's best candidate), O.mean, O.log, O.state.npz (resume with --resume). Search state lives in the repo, never in /tmp.
"""
import argparse
import json
import multiprocessing as mp
import os
import sys
import time

import numpy as np

HERE = "/Users/erik/tungsten/bits/tungsten-robolab"
sys.path.insert(0, os.path.join(HERE, "playground"))
sys.path.insert(0, os.path.join(HERE, "scratchpad", "soccer4"))
sys.path.insert(0, os.path.join(HERE, "scratchpad", "hazard"))
from search4 import read_params, describe, write  # noqa: E402


def hold_score(m, seconds):
    if m.get("error"):
        return -1e3
    b = float(m.get("bal1_raw") or 0.0)
    st = float(m.get("stand_time") or 0.0)
    s = 1.0 * min(b, seconds) + 0.5 * min(st, seconds)
    if b >= seconds - 3.0 and not m.get("fallen") and st >= seconds - 0.11:
        s += 6.0
    return s


def worker(job):
    params, seed, controller, seconds, w_exp = job
    import wscan2
    wscan2.HERE = HERE
    r = wscan2.run({"tag": f"z|{seed}", "seed": seed, "pdict": params, "controller": os.path.relpath(controller, HERE), "seconds": seconds,
                    "mode": "1", "max_time": 310})
    if "error" in r:
        return -1e3, {"error": r["error"][:200]}
    sc = hold_score(r, seconds) - w_exp * float(r.get("e2") or 0.0)
    return sc, {k: r.get(k) for k in ("bal1_raw", "stand_time", "fallen", "e2", "e3", "e4", "nan_events", "pr_mg_late_mean", "pr_legf_late", "seg_oth_near3")}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--init", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--only", required=True)
    ap.add_argument("--set", default="")
    ap.add_argument("--env", default="myoChallengeSoccerP2-v0")
    ap.add_argument("--controller", required=True)
    ap.add_argument("--seconds", type=float, default=12.0)
    ap.add_argument("--k", type=int, default=24)
    ap.add_argument("--seed0", type=int, default=97100)
    ap.add_argument("--gens", type=int, default=12)
    ap.add_argument("--pop", type=int, default=12)
    ap.add_argument("--sigma", type=float, default=0.08)
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--rseed", type=int, default=1)
    ap.add_argument("--w_exp", type=float, default=20.0)
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
    state_path = a.out + ".state.npz"
    g0, best = 0, -1e18
    if a.resume and os.path.exists(state_path):
        z = np.load(state_path)
        es.mean, es.sigma, es.C, es.pc, es.ps, es.gen = z["mean"], float(z["sigma"]), z["C"], z["pc"], z["ps"], int(z["gen"])
        g0, best = int(z["g"]), float(z["best"])
        print(f"resumed at generation {g0}, best {best:.3f}", flush=True)
    log = open(a.out + ".log", "a")
    log.write(json.dumps({"start": time.strftime("%H:%M:%S"), "args": vars(a), "names": names, "resume": a.resume}) + "\n")
    t0 = time.time()
    with mp.get_context("spawn").Pool(a.workers) as pool:
        for g in range(g0, a.gens):
            seeds = [a.seed0 + g * a.k + i for i in range(a.k)]
            X = es.ask()
            if g == 0:
                X[0] = x0
            jobs = [(to_params(x), sd, ctl, a.seconds, a.w_exp) for x in X for sd in seeds]
            res = pool.map(worker, jobs, chunksize=1)
            k = len(seeds)
            sc = np.array([np.mean([res[i * k + j][0] for j in range(k)]) for i in range(len(X))])
            fails = [sum(1 for j in range(k) if res[i * k + j][1].get("fallen") or (res[i * k + j][1].get("stand_time") or 0) < a.seconds - 0.11 or (res[i * k + j][1].get("bal1_raw") or 0) < a.seconds - 5.5) for i in range(len(X))]
            e2 = [float(np.mean([res[i * k + j][1].get("e2") or 0.0 for j in range(k)])) for i in range(len(X))]
            es.tell(X, sc)
            i = int(np.argmax(sc))
            if sc[i] > best:
                best = float(sc[i])
                write(a.out, to_params(X[i]), [f"zsearch {a.note}: gen {g + 1} score {sc[i]:.3f} fails {fails[i]}/{k} e2 {e2[i]:.4f} seeds {seeds[0]}..{seeds[-1]}"])
            write(a.out + ".mean", to_params(es.mean), [f"zsearch mean after gen {g + 1} {a.note}"])
            np.savez(state_path, mean=es.mean, sigma=es.sigma, C=es.C, pc=es.pc, ps=es.ps, gen=es.gen, g=g + 1, best=best)
            line = {"gen": g + 1, "t": round(time.time() - t0), "best": round(best, 3), "gen_best": round(float(sc[i]), 3), "gen_mean": round(float(np.mean(sc)), 3),
                    "x0_score": round(float(sc[0]), 3) if g == 0 else None, "fails_best": f"{fails[i]}/{k}", "fails_x0": f"{fails[0]}/{k}" if g == 0 else None,
                    "fails_mean": round(float(np.mean(fails)), 2), "e2_best": round(e2[i], 4), "e2_mean": round(float(np.mean(e2)), 4), "sigma": round(float(es.sigma), 4)}
            print(json.dumps(line), flush=True)
            log.write(json.dumps(line) + "\n")
            log.flush()


if __name__ == "__main__":
    main()
