"""Robust oracle for one stroke: one muscle program for many starts.

    .venv/bin/python scratchpad/btl2/oracle_multi.py --seeds 801,809,... --val 834,835,... --lead 32 --gens 200 --pop 60 \
        --workers 2 --out scratchpad/btl2/runs/om_left.npz

Each start is a recorded A4 run (snapshots around the left hand's stroke). The program starts `lead` ticks (5 ms) before the
ball's predicted rising crossing of z 0.62 after its first floor bounce (the time the skill would know exactly), overrides the
16 left-arm muscles for `window` seconds and lets the recording play on. The score is the mean of oracle_search.evaluate over
the starts; validation starts are scored with the best program at the end (and every 25 generations).
"""
import argparse
import os
import sys
import time

import numpy as np

sys.path.insert(0, "playground")
sys.path.insert(0, "playground/tasks")
sys.path.insert(0, "scratchpad/btl2")
from multiprocessing import get_context  # noqa: E402

import oracle_lib as O  # noqa: E402
from common import load  # noqa: E402
import oracle_search as S  # noqa: E402

_W = {}


def crossing_tick(rec, z=0.62, bounce_no=2):
    """First tick where the ball's centre rises through z after the `bounce_no`-th floor bounce (the launch's is the first,
    pass 1's the second: the ball the left hand receives)."""
    ball, bv = rec["ball"], rec["ballv"]
    nb = 0
    low = True
    for k in range(1, len(ball)):
        rebound = ball[k, 2] < 0.16 and bv[k, 2] > 0 and bv[k - 1, 2] <= 0
        if rebound:
            nb += 1
        if nb >= bounce_no and ball[k, 2] >= z and bv[k, 2] > 0:
            return k
    return None


def ball_before(rec, k):
    """The ball's centre before tick k (the state the sensors at tick k report), from the recorded trace."""
    return rec["ball"][k - 1]


def trigger_tick(rec, rp, bounce_no, lead=0.165, height=0.62):
    """The tick at which the skill's trigger fires: the first tick after the `bounce_no`-th floor rebound with the ball off the
    floor whose predicted rising crossing of `height` is within `lead` seconds (the prediction, not the actual crossing: the ball
    may be intercepted before it gets there)."""
    ball, bv = rec["ball"], rec["ballv"]
    nb = 0
    for k in range(1, len(ball)):
        if ball[k, 2] < 0.16 and bv[k, 2] > 0 and bv[k - 1, 2] <= 0:
            nb += 1
        if nb >= bounce_no and k in rec["snaps"]:
            # the skill ignores the sensors while the ball is on the floor (centre below 0.14 m)
            if ball_before(rec, k)[2] < 0.14:
                continue
            pc = rp.pred_cross(k, height)
            if pc is not None and pc[2] <= lead:
                return k
    return None


def init_worker(recs, cfg):
    _W["cfg"] = cfg
    _W["rp"] = {}
    for key, rec in recs.items():
        _W["rp"][key] = O.Replay(rec)
    _W["idx"] = None


def program_from(x, cfg, base, n):
    idx, kt, nprog = cfg["idx"], cfg["kt"], cfg["nprog"]
    X = np.clip(x.reshape(len(idx), len(kt)), 0.0, 1.0)
    ov = {}
    for r, mi in enumerate(idx):
        arr = base[:n, mi].copy()
        arr[:nprog + 1] = np.interp(np.arange(nprog + 1), kt, X[r])
        ov[mi] = arr
    return ov


def eval_one(job):
    x, key = job
    cfg = _W["cfg"]
    rp = _W["rp"][key]
    ks = cfg["kstart"][key]
    n = cfg["n"]
    base = rp.rec["acts"][ks:ks + n + 1]
    pc = 0 if cfg["who"] == "l" else 1

    def stop(i, pos, vel, cf):
        # the evaluation ends at the rise's arrival: after the passer's touch and the next bounce, the ball rising through z 0.60
        # (or the receiver's touch)
        if i < 20 or vel[i, 2] <= 0 or pos[i, 2] < 0.60:
            return False
        return bool(np.any(cf[:i + 1, pc] > 0.3)) and bool(np.any(cf[:i + 1, 2] > 0.2))

    out = rp.run(program_from(x, cfg, base, n), ticks=n, start=ks, stop=stop, hand_col=pc)
    return S.evaluate(out, cfg["mode"], cfg["who"])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seeds", required=True)
    ap.add_argument("--val", default="")
    ap.add_argument("--params", default="params/dribble_btl_a4.txt")
    ap.add_argument("--ctl", default="bin/challengers/btl2-b1")
    ap.add_argument("--lead", type=int, default=32, help="program start, ticks before the predicted rising crossing of z 0.62")
    ap.add_argument("--window", type=float, default=0.45)
    ap.add_argument("--eval", type=float, default=0.80)
    ap.add_argument("--dk", type=int, default=5)
    ap.add_argument("--gens", type=int, default=200)
    ap.add_argument("--pop", type=int, default=60)
    ap.add_argument("--sigma", type=float, default=0.12)
    ap.add_argument("--workers", type=int, default=2)
    ap.add_argument("--muscles", default="left_arm")
    ap.add_argument("--hand", default="l")
    ap.add_argument("--bounce-no", type=int, default=2, help="the ball's rising crossing after this floor bounce anchors the program (2: pass 1's bounce, 3: the return's)")
    ap.add_argument("--require", type=int, default=0, help="keep only starts whose first N passes were received (task's pass log)")
    ap.add_argument("--t-lo", type=float, default=1.70)
    ap.add_argument("--t-hi", type=float, default=2.40)
    ap.add_argument("--t-end", type=float, default=3.0)
    ap.add_argument("--mode", default="full")
    ap.add_argument("--init", default="")
    ap.add_argument("--cma-seed", type=int, default=3)
    ap.add_argument("--batch", type=int, default=0, help="rank each generation on a random subset of this many training starts (0: all); the CMA mean is scored on all of them every --full gens")
    ap.add_argument("--full", type=int, default=10)
    ap.add_argument("--cache", default="scratchpad/btl2/runs/rec_cache.npz")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    import pickle
    import practice as pr
    params = load(a.params)
    seeds = [int(s) for s in a.seeds.split(",")]
    val = [int(s) for s in a.val.split(",")] if a.val else []
    n = int(round(a.eval / 0.005))
    nprog = int(round(a.window / 0.005))
    recs, kstart = {}, {}
    skipped = []
    t0 = time.time()
    cachef = a.cache + ".pkl"
    cache = pickle.load(open(cachef, "rb")) if os.path.exists(cachef) else {}
    for sd in seeds + val:
        key = (sd, a.params, a.ctl, a.t_lo, a.t_hi, a.t_end)
        if key not in cache:
            rec = O.record(sd, params, a.ctl, a.t_lo, a.t_end, t_last=a.t_hi)
            cache[key] = rec
            pickle.dump(cache, open(cachef, "wb"))
        rec = cache[key]
        kc = crossing_tick(rec, bounce_no=a.bounce_no)
        if kc is None or (kc - a.lead) not in rec["snaps"]:
            skipped.append(sd)
            continue
        recs[sd] = rec
        kstart[sd] = kc - a.lead
    seeds = [sd for sd in seeds if sd in recs]
    val = [sd for sd in val if sd in recs]
    if skipped:
        print("skipped (no rising crossing after bounce %d in the window):" % a.bounce_no, skipped, flush=True)
    if a.require:
        def received(rec):
            pl = rec["pass_log"]
            return len(pl) >= a.require and all(pl[i]["outcome"] == "ok" and pl[i]["gate"] and pl[i]["body"] == 0 for i in range(a.require))
        seeds = [sd for sd in seeds if received(recs[sd])]
        val = [sd for sd in val if received(recs[sd])]
        print("kept", len(seeds), "training and", len(val), "validation starts with passes 1..%d received" % a.require, seeds, val, flush=True)
    print(f"recorded {len(recs)} starts in {time.time() - t0:.0f}s; start ticks {[kstart[s] for s in seeds]}", flush=True)
    any_rec = recs[seeds[0]]
    idx = S.muscle_set(any_rec["names"], a.muscles)
    kt = np.arange(0, nprog + 1, a.dk)
    cfg = {"idx": idx, "kt": kt, "nprog": nprog, "kstart": kstart, "n": n, "mode": a.mode, "who": a.hand}
    print(f"muscles {len(idx)} knots {len(kt)} dims {len(idx) * len(kt)}", flush=True)
    # the start: the recordings sampled at the knots, averaged over the starts and smoothed
    x0 = np.zeros((len(idx), len(kt)))
    for sd in seeds:
        base = recs[sd]["acts"][kstart[sd]:kstart[sd] + n + 1]
        for r, mi in enumerate(idx):
            for j, k in enumerate(kt):
                lo, hi = max(0, k - 2), min(len(base), k + 3)
                x0[r, j] += base[lo:hi, mi].mean() / len(seeds)
    x0 = x0.reshape(-1)
    if a.init and os.path.exists(a.init):
        z = np.load(a.init)
        x0 = z["x"]
        print("init from", a.init, flush=True)
    es = pr.CMA(x0, a.sigma, a.pop, seed=a.cma_seed)
    with get_context("spawn").Pool(a.workers, initializer=init_worker, initargs=(recs, cfg)) as pool:
        def score(xs, keys):
            jobs = [(x, k) for x in xs for k in keys]
            res = pool.map(eval_one, jobs, chunksize=max(1, len(jobs) // (4 * a.workers)))
            m = len(keys)
            return [(float(np.mean([r[0] for r in res[i * m:(i + 1) * m]])), [r[1] for r in res[i * m:(i + 1) * m]]) for i in range(len(xs))]

        def describe(rows, keys):
            good = 0
            out = []
            for sm in rows:
                ok = sm.get("touch") and sm.get("bounced") and sm.get("gate", 0) > 0 and sm.get("apex", 0) >= 0.58 and sm.get("body", 9) == 0 \
                    and float(np.hypot(*(np.array(sm["arrive"]) - (S.RIGHT_TARGET if a.hand == "l" else S.LEFT_TARGET)))) < 0.14
                good += 1 if ok else 0
            return good

        base_s = score([x0], seeds)[0]
        print(f"start mean J {base_s[0]:.3f}; good {describe(base_s[1], seeds)}/{len(seeds)}", flush=True)
        # baseline: the recorded controller itself (no override)
        best = (base_s[0], x0.copy())
        t1 = time.time()
        import random
        rnd = random.Random(a.cma_seed)
        for g in range(a.gens):
            xs = es.ask()
            keys = seeds if not a.batch or a.batch >= len(seeds) else rnd.sample(seeds, a.batch)
            res = score(xs, keys)
            sc = [r[0] for r in res]
            es.tell(xs, [-s for s in sc])
            k = int(np.argmin(sc))
            if not a.batch:
                if sc[k] < best[0]:
                    best = (sc[k], xs[k].copy())
                    np.savez(a.out, x=best[1], idx=np.array(idx), kt=kt, seeds=np.array(seeds), lead=a.lead, window=a.window, score=best[0])
            elif g % a.full == a.full - 1 or g == a.gens - 1:
                cand = es.mean.copy()
                fs = score([cand], seeds)[0]
                if fs[0] < best[0]:
                    best = (fs[0], cand)
                    np.savez(a.out, x=best[1], idx=np.array(idx), kt=kt, seeds=np.array(seeds), lead=a.lead, window=a.window, score=best[0])
                print(f"gen {g} mean-vector full-set J {fs[0]:.3f} good {describe(fs[1], seeds)}/{len(seeds)} (best {best[0]:.3f})", flush=True)
            if g % 5 == 0 or g == a.gens - 1:
                print(f"gen {g} best {best[0]:.3f} gen-best {sc[k]:.3f} good {describe(res[k][1], keys)}/{len(keys)} sigma {es.sigma:.3f} ({time.time() - t1:.0f}s)", flush=True)
            if val and (g % 25 == 24 or g == a.gens - 1):
                vs = score([best[1]], val)[0]
                print(f"   validation mean J {vs[0]:.3f} good {describe(vs[1], val)}/{len(val)}", flush=True)
    print("done")


if __name__ == "__main__":
    main()
