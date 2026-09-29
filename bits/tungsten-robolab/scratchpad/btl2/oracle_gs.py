"""Gain-scheduled robust oracle: the program is T0 + ux*Tx + uy*Ty, u the predicted crossing position of the arriving ball
(offset from the training mean, in units of its spread), so one table set covers the arrival's variation.

    .venv/bin/python scratchpad/btl2/oracle_gs.py --seeds ... --val ... --init prog.npz --out gs.npz [same stage options as oracle_multi.py]

`--init` may be a plain program (npz from oracle_multi.py: T0, gains start at 0) or a gs npz (x with 3 blocks).
"""
import argparse
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
import oracle_search as S  # noqa: E402
from common import load  # noqa: E402


import math


class SepCMA:
    """Separable CMA-ES (diagonal covariance), maximising, no box: the program is clipped where it is used."""

    def __init__(self, x0, sigma0, seed=1, popsize=None):
        n = len(x0)
        self.n = n
        self.rng = np.random.default_rng(seed)
        self.lam = popsize or 4 + int(3 * math.log(n))
        self.mu = self.lam // 2
        w = np.log(self.mu + 0.5) - np.log(np.arange(1, self.mu + 1))
        self.w = w / w.sum()
        self.mueff = 1.0 / np.sum(self.w ** 2)
        self.cc = (4 + self.mueff / n) / (n + 4 + 2 * self.mueff / n)
        self.cs = (self.mueff + 2) / (n + self.mueff + 5)
        c1 = 2 / ((n + 1.3) ** 2 + self.mueff)
        cmu = min(1 - c1, 2 * (self.mueff - 2 + 1 / self.mueff) / ((n + 2) ** 2 + self.mueff))
        scale = (n + 2) / 3.0
        self.c1 = min(1.0, c1 * scale)
        self.cmu = min(1.0 - self.c1, cmu * scale)
        self.damps = 1 + 2 * max(0, math.sqrt((self.mueff - 1) / (n + 1)) - 1) + self.cs
        self.chin = math.sqrt(n) * (1 - 1 / (4 * n) + 1 / (21 * n * n))
        self.mean = np.array(x0, float)
        self.sigma = sigma0
        self.C = np.ones(n)
        self.pc = np.zeros(n)
        self.ps = np.zeros(n)
        self.gen = 0

    def ask(self):
        z = self.rng.standard_normal((self.lam, self.n))
        return self.mean + self.sigma * z * np.sqrt(self.C)

    def tell(self, X, f):
        order = np.argsort(-np.asarray(f, float))
        X = np.asarray(X)[order]
        old = self.mean.copy()
        ys = (X[:self.mu] - old) / self.sigma
        yw = self.w @ ys
        self.mean = old + self.sigma * yw
        self.ps = (1 - self.cs) * self.ps + math.sqrt(self.cs * (2 - self.cs) * self.mueff) * yw / np.sqrt(self.C)
        hs = np.linalg.norm(self.ps) / math.sqrt(1 - (1 - self.cs) ** (2 * (self.gen + 1))) < (1.4 + 2 / (self.n + 1)) * self.chin
        self.pc = (1 - self.cc) * self.pc + hs * math.sqrt(self.cc * (2 - self.cc) * self.mueff) * yw
        self.C = ((1 - self.c1 - self.cmu) * self.C + self.c1 * (self.pc ** 2 + (1 - hs) * self.cc * (2 - self.cc) * self.C)
                  + self.cmu * (self.w @ (ys ** 2)))
        self.C = np.maximum(self.C, 1e-20)
        self.sigma *= math.exp((self.cs / self.damps) * (np.linalg.norm(self.ps) / self.chin - 1))
        self.gen += 1


_W = {}


def init_worker(recs, cfg):
    _W["cfg"] = cfg
    S.ARR.update(cfg.get("arr", {}))
    _W["rp"] = {k: O.Replay(r) for k, r in recs.items()}


def program_gs(x, cfg, base, n, u):
    """T0 + sum_i u_i T_i (each gain block bounded to +-gmax), bounded to [0, 1] at the knots, interpolated to the ticks. The features u are the
    predicted crossing (x, y) then the posture features (--zj); a program with fewer feature blocks than u simply ignores the rest."""
    idx, kt, nprog = cfg["idx"], cfg["kt"], cfg["nprog"]
    nm, K = len(idx), len(kt)
    nb = len(x) // (nm * K)
    T = x.reshape(nb, nm, K)
    G = cfg["gmax"]
    X = T[0].copy()
    for i in range(1, nb):
        X = X + u[i - 1] * np.clip(T[i], -G, G)
    X = np.clip(X, 0.0, 1.0)
    ov = {}
    for r, mi in enumerate(idx):
        arr = base[:n, mi].copy()
        arr[:nprog + 1] = np.interp(np.arange(nprog + 1), kt, X[r])
        ov[mi] = arr
    return ov


def stage_features(rp, ks, hand, zj):
    """The stage's raw features at the trigger tick: the ball's predicted rising crossing (x, y) then the stroking arm's posture (zj)."""
    pc = rp.pred_cross(ks)
    if pc is None:
        return None
    return np.array(list(pc[:2]) + (rp.posture(ks, hand, zj) if zj else []))


def eval_one(job):
    x, key, jit = job
    cfg = _W["cfg"]
    rp = _W["rp"][key]
    ks = cfg["kstart"][key]
    n = cfg["n"]
    base = rp.rec["acts"][ks:ks + n + 1]
    pc = 0 if cfg["who"] == "l" else 1

    def stop(i, pos, vel, cf):
        if i < 20 or vel[i, 2] <= 0 or pos[i, 2] < 0.60:
            return False
        return bool(np.any(cf[:i + 1, pc] > 0.3)) and bool(np.any(cf[:i + 1, 2] > 0.2))

    out = rp.run(program_gs(x, cfg, base, n, cfg["u"][key] + jit), ticks=n, start=ks, stop=stop, hand_col=pc)
    return S.evaluate(out, cfg["mode"], cfg["who"])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seeds", required=True)
    ap.add_argument("--val", default="")
    ap.add_argument("--params", default="params/dribble_btl_a4.txt")
    ap.add_argument("--ctl", default="bin/challengers/btl2-b8")
    ap.add_argument("--lead", type=int, default=32)
    ap.add_argument("--window", type=float, default=0.40)
    ap.add_argument("--eval", type=float, default=0.80)
    ap.add_argument("--dk", type=int, default=5)
    ap.add_argument("--gens", type=int, default=300)
    ap.add_argument("--pop", type=int, default=48)
    ap.add_argument("--sigma", type=float, default=0.05)
    ap.add_argument("--gsigma", type=float, default=0.03, help="initial step of the gain blocks relative to sigma")
    ap.add_argument("--workers", type=int, default=2)
    ap.add_argument("--muscles", default="left_arm")
    ap.add_argument("--hand", default="l")
    ap.add_argument("--bounce-no", type=int, default=2)
    ap.add_argument("--require", type=int, default=0)
    ap.add_argument("--t-lo", type=float, default=1.70)
    ap.add_argument("--t-hi", type=float, default=2.40)
    ap.add_argument("--t-end", type=float, default=3.0)
    ap.add_argument("--mode", default="full")
    ap.add_argument("--init", required=True)
    ap.add_argument("--batch", type=int, default=10)
    ap.add_argument("--full", type=int, default=10)
    ap.add_argument("--cma-seed", type=int, default=5)
    ap.add_argument("--gmax", type=float, default=1.0, help="bound of each gain entry (activation per sigma of the arrival feature)")
    ap.add_argument("--pos-dz", type=float, default=0.04, help="dead zone (m) of the arrival position error")
    ap.add_argument("--vel-dz", type=float, default=0.25, help="dead zone (m/s) of the arrival velocity error")
    ap.add_argument("--target", default="", help="arrival position target x,y (default: the other hand's nominal spot)")
    ap.add_argument("--vt", default="", help="arrival horizontal velocity target vx,vy")
    ap.add_argument("--no-pre", action="store_true", help="do not count arm/body contacts on the incoming ball before the palm's first touch (the launch pass has no incoming pass)")
    ap.add_argument("--ujit", type=float, default=0.10, help="jitter of the arrival feature (sigma units) in training rollouts")
    ap.add_argument("--w-pos", type=float, default=2.0, help="weight (per m) of the arrival position error beyond its dead zone")
    ap.add_argument("--w-vel", type=float, default=0.6, help="weight (per m/s) of the arrival velocity error beyond its dead zone")
    ap.add_argument("--fresh-gains", action="store_true", help="keep the init's T0 (re-expressed at this run's nominal features) but start every gain block at zero")
    ap.add_argument("--t0-only", action="store_true", help="with --fresh-gains: the init's T0 exactly as fitted (no shift to this run's nominal features)")
    ap.add_argument("--zj", default="", help="posture feature joints of the stroking arm (indices into POSTURE_JOINTS), e.g. 4,1,3")
    ap.add_argument("--zfloor", type=float, default=0.01, help="floor of a posture feature's spread")
    ap.add_argument("--no-renorm", action="store_true", help="use the init's blocks as they are even if its feature nominal / spread differ from this run's")
    ap.add_argument("--cache", default="scratchpad/btl2/runs/rec_cache.npz")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    params = load(a.params)
    seeds = [int(s) for s in a.seeds.split(",")]
    val = [int(s) for s in a.val.split(",")] if a.val else []
    n = int(round(a.eval / 0.005))
    nprog = int(round(a.window / 0.005))
    cachef = a.cache + ".pkl"
    cache = pickle.load(open(cachef, "rb")) if os.path.exists(cachef) else {}
    recs, kstart, skipped = {}, {}, []
    t0 = time.time()
    for sd in seeds + val:
        key = (sd, a.params, a.ctl, a.t_lo, a.t_hi, a.t_end)
        if key not in cache:
            cache[key] = O.record(sd, params, a.ctl, a.t_lo, a.t_end, t_last=a.t_hi)
            pickle.dump(cache, open(cachef, "wb"))
        rec = cache[key]
        ks = M.trigger_tick(rec, O.Replay(rec), a.bounce_no, lead=a.lead * 0.005 + 0.005)
        if ks is None or ks not in rec["snaps"]:
            skipped.append(sd)
            continue
        recs[sd] = rec
        kstart[sd] = ks
    seeds = [s for s in seeds if s in recs]
    val = [s for s in val if s in recs]
    if a.require:
        def received(rec):
            # the first passes crossed the gate without hitting a leg (whoever failed to take the ball is not the question)
            pl = rec["pass_log"]
            return len(pl) >= a.require and all(pl[i]["gate"] and pl[i]["body"] == 0 for i in range(a.require))
        seeds = [s for s in seeds if received(recs[s])]
        val = [s for s in val if received(recs[s])]
    print(f"{len(seeds)} training, {len(val)} validation starts (skipped {len(skipped)}) recorded in {time.time() - t0:.0f}s", flush=True)
    # the arrival features
    zj = [int(v) for v in a.zj.split(",")] if a.zj else []
    nf = 2 + len(zj)
    feat = {}
    for sd in seeds + val:
        rp0 = O.Replay(recs[sd])
        feat[sd] = stage_features(rp0, kstart[sd], a.hand, zj)
    ok_seeds = [s for s in seeds if feat[s] is not None]
    F = np.array([feat[s] for s in ok_seeds])
    nom = F.mean(axis=0)
    sc = np.maximum(F.std(axis=0), np.array([0.02, 0.02] + [a.zfloor] * len(zj)))
    print("arrival feature nominal", np.round(nom, 3).tolist(), "spread", np.round(sc, 3).tolist(), flush=True)
    seeds = ok_seeds
    val = [s for s in val if feat[s] is not None]
    u = {s: np.clip((feat[s] - nom) / sc, -2.5, 2.5) for s in seeds + val}
    any_rec = recs[seeds[0]]
    idx = S.muscle_set(any_rec["names"], a.muscles)
    kt = np.arange(0, nprog + 1, a.dk)
    nm, K = len(idx), len(kt)
    cfg = {"idx": idx, "kt": kt, "nprog": nprog, "kstart": {s: kstart[s] for s in seeds + val}, "n": n, "mode": a.mode, "who": a.hand, "gmax": a.gmax, "arr": {"pos_dz": a.pos_dz, "vel_dz": a.vel_dz, "target": [float(v) for v in a.target.split(",")] if a.target else None, "vt": [float(v) for v in a.vt.split(",")] if a.vt else None, "pre": not a.no_pre, "w_pos": a.w_pos, "w_vel": a.w_vel},
           "u": {s: u[s] for s in seeds + val}}
    z = np.load(a.init)
    nb = 1 + nf                       # T0, one gain block per feature
    blocks0 = len(z["x"]) // (nm * K)
    T = z["x"].reshape(blocks0, nm, K)
    if blocks0 == 1:
        T = np.concatenate([T, np.zeros((nb - 1, nm, K))])
    elif "nom" in z.files and "sc" in z.files and not a.no_renorm:
        # the init was fitted with its own feature nominal / spread: re-express its program in this run's units (the same function of
        # the raw features: T0' = T0 + sum d_i T_i, T_i' = r_i T_i); blocks of features the init did not have start at zero
        nf0 = blocks0 - 1
        zj0 = [int(v) for v in z["zj"]] if "zj" in z.files else []
        assert zj0 == zj[:len(zj0)], f"init posture joints {zj0} do not match {zj}"
        dd = (nom[:nf0] - z["nom"][:nf0]) / z["sc"][:nf0]
        rr = sc[:nf0] / z["sc"][:nf0]
        T0 = T[0].copy()
        for i in range(nf0):
            T0 = T0 + dd[i] * T[1 + i]
        Tn = np.zeros((nb, nm, K))
        Tn[0] = T0
        for i in range(nf0):
            Tn[1 + i] = T[1 + i] * rr[i]
        T = Tn
        if a.fresh_gains:
            T[1:] = 0.0
            if a.t0_only:
                T[0] = z["x"].reshape(blocks0, nm, K)[0]
        print("init re-expressed in this run's feature units: shift", np.round(dd, 2).tolist(), "scale", np.round(rr, 2).tolist(), flush=True)
    elif blocks0 < nb:
        T = np.concatenate([T, np.zeros((nb - blocks0, nm, K))])
    x0 = T.reshape(-1).copy()
    print(f"muscles {nm} knots {K} dims {len(x0)}", flush=True)
    opt = SepCMA(x0, a.sigma, seed=a.cma_seed, popsize=a.pop)
    # smaller initial steps for the gain blocks
    opt.C[nm * K:] = a.gsigma ** 2 / max(a.sigma ** 2, 1e-12) * 0 + (a.gsigma / a.sigma) ** 2 if a.sigma > 0 else 1.0
    rnd = random.Random(a.cma_seed)
    tgt = (S.RIGHT_TARGET if a.hand == "l" else S.LEFT_TARGET)

    def describe(rows):
        g = 0
        for sm in rows:
            ok = sm.get("touch") and sm.get("bounced") and sm.get("gate", 0) > 0 and sm.get("apex", 0) >= 0.58 and sm.get("body", 9) == 0 \
                and float(np.hypot(*(np.array(sm["arrive"]) - tgt))) < 0.14
            g += 1 if ok else 0
        return g

    with get_context("spawn").Pool(a.workers, initializer=init_worker, initargs=(recs, cfg)) as pool:
        def score(xs, keys, jit=0.0):
            jv = {k: tuple(rnd.gauss(0, jit) for _ in range(nf)) if jit > 0 else (0.0,) * nf for k in keys}
            jobs = [(x, k, np.array(jv[k])) for x in xs for k in keys]
            res = pool.map(eval_one, jobs, chunksize=max(1, len(jobs) // (4 * a.workers)))
            m = len(keys)
            return [(float(np.mean([r[0] for r in res[i * m:(i + 1) * m]])), [r[1] for r in res[i * m:(i + 1) * m]]) for i in range(len(xs))]

        b0 = score([x0], seeds)[0]
        best = (b0[0], x0.copy())
        print(f"start full-set J {b0[0]:.3f} good {describe(b0[1])}/{len(seeds)}", flush=True)
        t1 = time.time()
        for g in range(a.gens):
            xs = opt.ask()
            keys = seeds if a.batch >= len(seeds) else rnd.sample(seeds, a.batch)
            res = score(xs, keys, a.ujit)
            sc_ = np.array([r[0] for r in res])
            opt.tell(xs, -sc_)
            k = int(np.argmin(sc_))
            if g % a.full == a.full - 1 or g == a.gens - 1:
                cand = opt.mean.copy()
                fs = score([cand], seeds)[0]
                if fs[0] < best[0]:
                    best = (fs[0], cand)
                    np.savez(a.out, x=best[1], idx=np.array(idx), kt=kt, seeds=np.array(seeds), lead=a.lead, window=a.window, score=best[0],
                             nom=nom, sc=sc, gs=1, gmax=a.gmax, zj=np.array(zj, dtype=int), hand=a.hand)
                print(f"gen {g} mean-vector full-set J {fs[0]:.3f} good {describe(fs[1])}/{len(seeds)} (best {best[0]:.3f})", flush=True)
                if val:
                    vs = score([best[1]], val)[0]
                    print(f"   validation J {vs[0]:.3f} good {describe(vs[1])}/{len(val)}", flush=True)
            if g % 5 == 0:
                print(f"gen {g} gen-best {sc_[k]:.3f} sigma {opt.sigma:.3f} ({time.time() - t1:.0f}s)", flush=True)
    print("done")


if __name__ == "__main__":
    main()
