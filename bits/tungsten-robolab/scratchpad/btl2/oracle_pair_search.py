"""Joint search of the left return (stage 0) and the right return (stage 1) on the two-stage replay.

    .venv/bin/python scratchpad/btl2/oracle_pair_search.py --seeds ... --val ... --params P.txt --ctl bin/challengers/btl2-b10 \
        --initL left.npz --initR right.npz --out pair.npz

The chain is recorded closed loop with P (the current pair), so the right arm's hover before its program is the one the
skill produces; both programs are then searched together on the same trace (oracle_pair.run_pair): the score is the left
hand's release (gate, no leg hit, bounce, energy; NOT its arrival point) plus the right hand's stroke on the ball the left
one sends. Writes an npz for each stage (`<out>_L.npz`, `<out>_R.npz`, gain-scheduled format).
"""
import argparse
import math
import os
import pickle
import random
import sys
import time

import numpy as np

sys.path.insert(0, "playground")
sys.path.insert(0, "playground/tasks")
sys.path.insert(0, "scratchpad/btl2")
from multiprocessing import get_context  # noqa: E402

import oracle_lib as O  # noqa: E402
import oracle_multi as M  # noqa: E402
import oracle_pair as P  # noqa: E402
import oracle_search as S  # noqa: E402
from common import load  # noqa: E402
from oracle_gs import SepCMA  # noqa: E402

_W = {}


def init_worker(recs, cfg):
    _W["cfg"] = cfg
    _W["rp"] = {k: O.Replay(r) for k, r in recs.items()}


def unpack(x, cfg):
    nm, K = cfg["nm"], cfg["K"]
    h = 3 * nm * K
    return x[:h].reshape(3, nm, K), x[h:].reshape(3, nm, K)


def slice_out(out, a):
    return {"pos": out["pos"][a:], "vel": out["vel"][a:], "cf": out["cf"][a:], "legs": out["legs"][a:], "palm": out["palm"][a:],
            "prehit": out["prehit"][a:], "t0": out["t0"]}


def eval_one(job):
    x, key, jitL, jitR = job
    cfg = _W["cfg"]
    rp = _W["rp"][key]
    ks = cfg["kstart"][key]
    TL, TR = unpack(x, cfg)
    uL = cfg["uL"][key] + jitL
    nomR, scR = cfg["nomR"], cfg["scR"]
    feat_R = lambda xy: np.clip((xy - nomR) / scR, -2.5, 2.5)
    out = P.run_pair(rp, ks, cfg, TL, uL, TR, feat_R, jitR=jitR, n=cfg["n"], stop=True)
    JL, smL = S.evaluate(out, "full", "l", arrival=False)
    rel = out["release_tick"]
    if smL.get("touch") and smL.get("bounced") and rel is not None and rel + 1 < len(out["pos"]) - 5:
        JR, smR = S.evaluate(slice_out(out, rel + 1), "full", "r")
    else:
        JR, smR = 20.0, {}
    good = bool(smL.get("touch") and smL.get("gate", 0) > 0 and smL.get("body", 9) == 0 and smR.get("touch") and smR.get("gate", 0) > 0
                and smR.get("body", 9) == 0 and smR.get("apex", 0) >= 0.58)
    return JL + JR, {"JL": JL, "JR": JR, "good": good, "goodL": bool(smL.get("touch") and smL.get("gate", 0) > 0 and smL.get("body", 9) == 0)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seeds", required=True)
    ap.add_argument("--val", default="")
    ap.add_argument("--params", required=True)
    ap.add_argument("--ctl", default="bin/challengers/btl2-b10")
    ap.add_argument("--initL", required=True)
    ap.add_argument("--initR", required=True)
    ap.add_argument("--t-lo", type=float, default=1.70)
    ap.add_argument("--t-hi", type=float, default=2.40)
    ap.add_argument("--t-end", type=float, default=3.8)
    ap.add_argument("--eval", type=float, default=1.5)
    ap.add_argument("--gens", type=int, default=400)
    ap.add_argument("--pop", type=int, default=48)
    ap.add_argument("--batch", type=int, default=12)
    ap.add_argument("--full", type=int, default=10)
    ap.add_argument("--sigma", type=float, default=0.03)
    ap.add_argument("--gmax", type=float, default=1.0)
    ap.add_argument("--ujit", type=float, default=0.10)
    ap.add_argument("--workers", type=int, default=2)
    ap.add_argument("--require", type=int, default=1)
    ap.add_argument("--cache", default="scratchpad/btl2/runs/rec_pair")
    ap.add_argument("--cma-seed", type=int, default=5)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    params = load(a.params)
    seeds = [int(s) for s in a.seeds.split(",")]
    val = [int(s) for s in a.val.split(",")] if a.val else []
    cachef = a.cache + ".pkl"
    cache = pickle.load(open(cachef, "rb")) if os.path.exists(cachef) else {}
    recs, kstart, uL = {}, {}, {}
    zl, zr = np.load(a.initL), np.load(a.initR)
    idxL, idxR, kt = list(zl["idx"]), list(zr["idx"]), zl["kt"]
    nm, K = len(idxL), len(kt)
    nprog = int(kt[-1])
    t0 = time.time()
    feats = {}
    for sd in seeds + val:
        key = (sd, a.params, a.ctl, a.t_lo, a.t_hi, a.t_end)
        if key not in cache:
            cache[key] = O.record(sd, params, a.ctl, a.t_lo, a.t_end, t_last=a.t_hi)
            pickle.dump(cache, open(cachef, "wb"))
        rec = cache[key]
        pl = rec["pass_log"]
        if a.require and not (len(pl) >= a.require and all(pl[i]["gate"] and pl[i]["body"] == 0 for i in range(a.require))):
            continue
        rp0 = O.Replay(rec)
        ks = M.trigger_tick(rec, rp0, 2)
        if ks is None or ks not in rec["snaps"]:
            continue
        pc = rp0.pred_cross(ks)
        if pc is None:
            continue
        recs[sd] = rec
        kstart[sd] = ks
        feats[sd] = np.array(pc[:2])
    seeds = [s for s in seeds if s in recs]
    val = [s for s in val if s in recs]
    print(f"{len(seeds)} training, {len(val)} validation starts recorded in {time.time() - t0:.0f}s", flush=True)
    nomL, scL = zl["nom"], zl["sc"]
    uL = {s: np.clip((feats[s] - nomL) / scL, -2.5, 2.5) for s in seeds + val}
    cfg = {"idxL": idxL, "idxR": idxR, "kt": kt, "nprog": nprog, "G": a.gmax, "lead": 0.165, "nm": nm, "K": K,
           "touch_thr": params.get("touch_thr", 0.353), "release_thr": params.get("release_thr", 0.376), "push_min": params.get("push_min", 0.02),
           "kstart": kstart, "uL": uL, "nomR": zr["nom"], "scR": zr["sc"], "n": int(round(a.eval / 0.005))}
    x0 = np.concatenate([zl["x"], zr["x"]])
    print("dims", len(x0), flush=True)
    opt = SepCMA(x0, a.sigma, seed=a.cma_seed, popsize=a.pop)
    rnd = random.Random(a.cma_seed)

    with get_context("spawn").Pool(a.workers, initializer=init_worker, initargs=(recs, cfg)) as pool:
        def score(xs, keys, jit=0.0):
            jv = {k: (np.array([rnd.gauss(0, jit), rnd.gauss(0, jit)]), (rnd.gauss(0, jit), rnd.gauss(0, jit))) if jit > 0 else (np.zeros(2), (0.0, 0.0)) for k in keys}
            jobs = [(x, k, jv[k][0], jv[k][1]) for x in xs for k in keys]
            res = pool.map(eval_one, jobs, chunksize=max(1, len(jobs) // (4 * a.workers)))
            m = len(keys)
            out = []
            for i in range(len(xs)):
                rows = res[i * m:(i + 1) * m]
                out.append((float(np.mean([r[0] for r in rows])), [r[1] for r in rows]))
            return out

        def summ(rows):
            return sum(1 for r in rows if r["good"]), sum(1 for r in rows if r["goodL"])

        b0 = score([x0], seeds)[0]
        best = (b0[0], x0.copy())
        print(f"start full-set J {b0[0]:.3f} good(pair) {summ(b0[1])[0]}/{len(seeds)} goodL {summ(b0[1])[1]}", flush=True)
        t1 = time.time()
        for g in range(a.gens):
            xs = opt.ask()
            keys = seeds if a.batch >= len(seeds) else rnd.sample(seeds, a.batch)
            res = score(xs, keys, a.ujit)
            sc = np.array([r[0] for r in res])
            opt.tell(xs, -sc)
            k = int(np.argmin(sc))
            if g % a.full == a.full - 1 or g == a.gens - 1:
                cand = opt.mean.copy()
                fs = score([cand], seeds)[0]
                if fs[0] < best[0]:
                    best = (fs[0], cand)
                    h = 3 * nm * K
                    for tag, blk, z in (("L", best[1][:h], zl), ("R", best[1][h:], zr)):
                        np.savez(a.out + "_" + tag + ".npz", x=blk, idx=np.array(z["idx"]), kt=kt, lead=32, window=z["window"], score=best[0],
                                 nom=z["nom"], sc=z["sc"], gs=1, gmax=a.gmax)
                print(f"gen {g} mean-vector full-set J {fs[0]:.3f} good(pair) {summ(fs[1])[0]}/{len(seeds)} goodL {summ(fs[1])[1]} (best {best[0]:.3f})", flush=True)
                if val:
                    vs = score([best[1]], val)[0]
                    print(f"   validation J {vs[0]:.3f} good(pair) {summ(vs[1])[0]}/{len(val)} goodL {summ(vs[1])[1]}", flush=True)
            if g % 5 == 0:
                print(f"gen {g} gen-best {sc[k]:.3f} sigma {opt.sigma:.3f} ({time.time() - t1:.0f}s)", flush=True)
    print("done")


if __name__ == "__main__":
    main()
