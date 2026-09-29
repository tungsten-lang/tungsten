"""sep-CMA over a skill's tunables on saved-state REPLAYS (kreplay.py): every candidate is run from a checkpoint of each pack of a fixed set,
scored by kreplay.score (a goal is worth 10 more than a plain kick). Resumable (state pickled every generation).

  ksearch.py --init P --controller C --only a,b,c --glob 'p1base_n0.05_*' --glob 'p1base_n0.1_*' --kind swing|touch
             --out out/K1.txt --gens 20 --pop 12 --sigma 0.15 [--good] [--train 40] [--seed 1] [--workers 2]

Parameters that are read before the checkpoint change the fed replies of the controller (replay mismatch): such a replay scores -5, so a
search steers away from them (better: leave them out of --only).
"""
import argparse
import glob
import json
import multiprocessing as mp
import os
import pickle
import re
import sys
import time

import numpy as np

sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/kick")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/soccer4")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
import kcommon as K
import kreplay as R

_W = None
_PACKS = {}


def _init(controller):
    global _W
    _W = R.Worker(controller)


def get_pack(path):
    p = _PACKS.get(path)
    if p is None:
        p = R.load(path)
        _PACKS[path] = p
    return p


def checkpoint(pack, kind, lead=2):
    if kind == "swing":
        return R.first_tick(pack, "swing") - lead
    if kind == "touch":
        t = pack["row"]["t_touch"]
        return int(round(t / 0.01)) - 1 - lead
    return int(kind)


def job(a):
    path, params, controller, kind, penal = a
    pack = get_pack(path)
    k = checkpoint(pack, kind)
    try:
        m = _W.replay(pack, k, params, controller=controller)
    except Exception as e:  # a crashing candidate scores worst
        return -6.0, {"error": str(e)[:100]}
    if m["replay_bad"]:
        return -5.0, {"bad": m["replay_bad"]}
    keep = ["goal", "ball_speed", "t_touch", "cross_y", "pred_y", "fallen", "t_fall", "t_cross"]
    row = {kk: m.get(kk) for kk in keep}
    row["ok"] = R.kick_ok(m)
    return R.score(m), row


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--init", required=True)
    ap.add_argument("--controller", required=True)
    ap.add_argument("--only", required=True)
    ap.add_argument("--glob", action="append", required=True)
    ap.add_argument("--kind", default="swing")
    ap.add_argument("--out", required=True)
    ap.add_argument("--gens", type=int, default=20)
    ap.add_argument("--pop", type=int, default=12)
    ap.add_argument("--sigma", type=float, default=0.15)
    ap.add_argument("--workers", type=int, default=2)
    ap.add_argument("--good", action="store_true", help="only packs whose own rollout's contact was good (speed and window)")
    ap.add_argument("--train", type=int, default=0, help="use the first N packs (after filtering); the rest stay for validation")
    ap.add_argument("--seeds", default="", help="keep packs whose seed is in lo:hi")
    ap.add_argument("--dir", default="p1base", help="dump directory under ckpt/")
    ap.add_argument("--set", default="")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--note", default="")
    a = ap.parse_args()
    from search import SepCMA
    from search4 import describe, write

    init = K.read_params(a.init)
    for kv in a.set.split(","):
        if "=" in kv:
            k, v = kv.split("=")
            init[k.strip()] = float(v)
    ctl = os.path.abspath(a.controller)
    tun = {t[0]: t for t in describe(init, "myoChallengeSoccerP2-v0", ctl)}
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

    files = []
    for g in a.glob:
        files += sorted(glob.glob(R.CK + a.dir + "/" + g + ".pkl.gz") if "/" not in g else glob.glob(g))
    if a.seeds:
        lo_, hi_ = [int(v) for v in a.seeds.split(":")]
        files = [f for f in files if lo_ <= int(re.search(r"_s(\d+)\.pkl", f).group(1)) < hi_]
    if a.good:
        keep = []
        for f in files:
            r = R.load(f)["row"]
            cy = r["cross_y"]
            if (r["ball_speed"] or 0) > 8.5 and cy is not None and 0.5 < abs(cy) < 3.2:
                keep.append(f)
        files = keep
    if a.train:
        files = files[:a.train]
    print(f"{len(files)} packs, {len(names)} parameters, kind {a.kind}", flush=True)
    state_path = a.out + ".state.pkl"
    if os.path.exists(state_path):
        es, g0, best = pickle.load(open(state_path, "rb"))
        print("resumed at generation", g0, flush=True)
    else:
        es, g0, best = SepCMA(x0, sigma0=a.sigma, seed=a.seed, popsize=a.pop), 0, -1e18
    log = open(a.out + ".log", "a")
    log.write(json.dumps({"start": time.strftime("%H:%M:%S"), "args": vars(a), "names": names, "n": len(files)}) + "\n")
    t0 = time.time()
    with mp.Pool(a.workers, initializer=_init, initargs=(ctl,)) as pool:
        for g in range(g0, a.gens):
            X = es.ask()
            if g == 0:
                X[0] = x0
            jobs = [(f, to_params(x), ctl, a.kind, 0) for x in X for f in files]
            res = pool.map(job, jobs, chunksize=4)
            n = len(files)
            sc = np.array([np.mean([res[i * n + j][0] for j in range(n)]) for i in range(len(X))])
            oks = [sum(1 for j in range(n) if res[i * n + j][1].get("ok")) for i in range(len(X))]
            es.tell(X, sc)
            i = int(np.argmax(sc))
            if sc[i] > best:
                best = float(sc[i])
                write(a.out, to_params(X[i]), [f"ksearch {a.note}: gen {g + 1} score {sc[i]:.3f} ok {oks[i]}/{n}"])
            write(a.out + ".mean", to_params(es.mean), [f"ksearch mean after gen {g + 1}"])
            pickle.dump((es, g + 1, best), open(state_path, "wb"))
            line = {"gen": g + 1, "t": round(time.time() - t0), "best": round(best, 3), "gen_best": round(float(sc[i]), 3), "gen_mean": round(float(np.mean(sc)), 3),
                    "ok_best": f"{oks[i]}/{n}", "ok_x0": f"{oks[0]}/{n}" if g == 0 else None, "sigma": round(float(es.sigma), 4)}
            print(json.dumps(line), flush=True)
            log.write(json.dumps(line) + "\n")
            log.flush()


if __name__ == "__main__":
    main()
