"""rses.py (sprint 5, agent S5): (1+lambda)-ES with FRESH SEEDS PER GENERATION and a VALIDATED ACCEPTANCE, for the LABELLED beyond-human sprinter.

Why not hsearch.py: its candidates run one fixed seed list, so the winner of a generation is the luckiest on THOSE seeds (S4: searches on 12-14
seeds fixed their own seeds, not the hazard: 9/56 unseen starts still fell). Here, every generation
  1. draws K training seeds from a large POOL (a fraction of them replayed from the seeds the incumbent fell on: the hard ones),
  2. evaluates the incumbent and lambda sparse mutations of it on those SAME seeds (common random numbers),
  3. takes the best offspring; only if it beats the incumbent on that draw is it VALIDATED on K2 other fresh seeds, and it is accepted
     only if it also beats the incumbent there (a lucky draw passes this with probability ~1/2, a harmful mutation rarely).
Every `--check-every` generations the incumbent runs on a fixed held-out CHECK set (falls / score are logged: an unbiased progress curve).
A margin term (`--margin W`) subtracts W x the run's max |torso pitch| after 2.5 s (metric p_max of tasks/sprint_touch_v4y.py): a smooth
signal (how close a surviving run came to a fall) beside the one-bit fall.

    .venv/bin/python scratchpad/sprint5/rses.py NAME INIT.txt --only "..." --exclude "..." --pool 15001-15999 --k 64 --k2 64 --lam 12 \\
        --seconds 10 --attrs objective=3,fall_pen=300 --check 14001-14128 --workers 6

Outputs: out/sprint5/NAME.log (one JSON line per generation), scratchpad/sprint5/NAME_best.txt (the incumbent, rewritten at each acceptance),
scratchpad/sprint5/NAME_g<N>.txt (a copy at every check). Everything is on the beyond-human body (env set below).
"""
import argparse
import json
import math
import multiprocessing as mp
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
os.environ["ROBOLAB_CALIB"] = "v4"
os.environ["ROBOLAB_PROFILE"] = "beyond"
os.environ["ROBOLAB_PROFILE_PARTS"] = "strength,speed,tendon,activation"
sys.path.insert(0, os.path.join(ROOT, "playground"))

import numpy as np  # noqa: E402


def parse_seeds(spec):
    out = []
    for tok in spec.split(","):
        tok = tok.strip()
        if not tok:
            continue
        if "-" in tok:
            lo, hi = tok.split("-")
            out += list(range(int(lo), int(hi) + 1))
        else:
            out.append(int(tok))
    return out


def job_score(job):
    """search.rollout plus the margin term; returns (score, fell, time, p_max, wall)."""
    from search import rollout
    task, params, seed, seconds, attrs, wmargin = job[:6]
    vfloor, vweight = (job[6], job[7]) if len(job) > 7 else (0.0, 0.0)
    s, m, wall = rollout((task, params, seed, seconds, attrs))
    pm = m.get("p_max")
    if wmargin and pm is not None and s > -1e8:
        s -= wmargin * pm
    # a speed floor on the sustained speed of a surviving run (so that stability is not bought with the 10 m/s the target needs)
    if vweight and not m.get("fell") and s > -1e8:
        s -= vweight * max(0.0, vfloor - float(m.get("steady_speed") or 0.0))
    return s, bool(m.get("fell")), float(m.get("time") or 0.0), pm, wall, m.get("peak_speed_1s")


def evaluate(pool, rep, X, seeds, a, wmargin):
    jobs = [(a.task, rep.decode(x), s, a.seconds, a.attrs_d, wmargin, a.vfloor, a.vweight) for x in X for s in seeds]
    res = pool.map(job_score, jobs, chunksize=1)
    n, k = len(X), len(seeds)
    S = np.array([r[0] for r in res]).reshape(n, k)
    F = np.array([r[1] for r in res]).reshape(n, k)
    T = np.array([r[2] for r in res]).reshape(n, k)
    PK = np.array([(r[5] if r[5] is not None else 0.0) for r in res]).reshape(n, k)
    return S, F, T, PK


def write_params(path, rep, x, note):
    p = rep.decode(x)
    with open(path, "w") as f:
        f.write(f"# robolab params (sprint 5, rses.py): {note}\n# \n")
        for k in sorted(p):
            if not k.startswith("__"):
                f.write(f"{k} {float(p[k])!r}\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("name")
    ap.add_argument("init")
    ap.add_argument("--task", default="sprint_touch_v4y")
    ap.add_argument("--controller", default=os.path.join(ROOT, "bin", "challengers", "run_gearx-s4b"))
    ap.add_argument("--only")
    ap.add_argument("--exclude")
    ap.add_argument("--box")
    ap.add_argument("--attrs", default="objective=3,fall_pen=300")
    ap.add_argument("--start", default="")
    ap.add_argument("--snap", default="")
    ap.add_argument("--pool", required=True)
    ap.add_argument("--k", type=int, default=64)
    ap.add_argument("--k2", type=int, default=64)
    ap.add_argument("--lam", type=int, default=12)
    ap.add_argument("--mut", type=float, default=6.0)
    ap.add_argument("--sigma", type=float, default=0.03)
    ap.add_argument("--seconds", type=float, default=10.0)
    ap.add_argument("--margin", type=float, default=0.0)
    ap.add_argument("--vfloor", type=float, default=0.0, help="steady-speed floor (m/s) of a surviving run")
    ap.add_argument("--vweight", type=float, default=0.0, help="score points lost per m/s below --vfloor")
    ap.add_argument("--hard", type=float, default=0.25, help="fraction of each draw replayed from the seeds the incumbent fell on")
    ap.add_argument("--gens", type=int, default=100000)
    ap.add_argument("--max-minutes", type=float, default=600.0)
    ap.add_argument("--check", default="")
    ap.add_argument("--check-seconds", type=float, default=0.0)
    ap.add_argument("--check-snap", default="", help="snapshot set of the CHECK rollouts (flying starts): e.g. run_v4_s5s, while training uses --snap")
    ap.add_argument("--check-every", type=int, default=5)
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--seed", type=int, default=1)
    a = ap.parse_args()
    os.environ["ROBOLAB_CONTROLLER"] = os.path.abspath(a.controller)
    if a.start:
        os.environ["RUN_NATURAL_START"] = a.start
    if a.snap:
        os.environ["ROBOLAB_SNAP"] = a.snap
    a.attrs_d = {kv.split("=")[0]: float(kv.split("=")[1]) for kv in a.attrs.split(",") if kv}
    from search import BoxRep, describe, parse_list
    from practice import read_params
    init = read_params(a.init)
    tun = describe(a.task, init)
    if a.box:
        box = {kv.split("=")[0]: tuple(float(x) for x in kv.split("=")[1].split(":")) for kv in a.box.split(",")}
        unknown = sorted(set(box) - {t[0] for t in tun})
        if unknown:
            raise SystemExit(f"--box names no tunable: {', '.join(unknown)}")
        tun = [(t[0], t[1], *box.get(t[0], (t[2], t[3]))) for t in tun]
    # a start value outside its declared box would be CLIPPED by BoxRep (changing the incumbent before the first mutation): widen such boxes
    widened = []
    tun2 = []
    for (nm, dflt, lo, hi) in tun:
        v = init.get(nm, dflt)
        if v < lo or v > hi:
            pad = 0.1 * (hi - lo)
            widened.append(f"{nm}={v:.4g} (box {lo:g}:{hi:g})")
            lo, hi = min(lo, v - pad), max(hi, v + pad)
        tun2.append((nm, dflt, lo, hi))
    tun = tun2
    if widened:
        print("boxes widened to hold the start values:", "; ".join(widened), flush=True)
    rep = BoxRep.from_tunables(tun, parse_list(a.only), parse_list(a.exclude), init, {})
    pool_seeds = parse_seeds(a.pool)
    check = parse_seeds(a.check) if a.check else []
    rng = np.random.default_rng(a.seed)
    os.makedirs(os.path.join(ROOT, "out", "sprint5"), exist_ok=True)
    logp = os.path.join(ROOT, "out", "sprint5", a.name + ".log")
    bestp = os.path.join(HERE, a.name + "_best.txt")
    log = open(logp, "a")
    t0 = time.time()
    print(f"rses {a.name}: {rep.n} tunables, pool {len(pool_seeds)} seeds, K {a.k}, K2 {a.k2}, lam {a.lam}, sigma {a.sigma}, {a.seconds} s, margin {a.margin}, "
          f"workers {a.workers}, controller {a.controller}", flush=True)
    x = rep.x0.copy()
    write_params(bestp, rep, x, f"start = {a.init}")
    sigma = a.sigma
    n_acc, hard, since_acc = 0, [], 0
    q = min(1.0, a.mut / rep.n)
    with mp.get_context("spawn").Pool(a.workers) as pool:
        def check_eval(gen):
            if not check:
                return None
            sec = a.check_seconds or a.seconds
            cattrs = dict(a.attrs_d)
            if a.check_snap:
                cattrs["snap"] = a.check_snap
            jobs = [(a.task, rep.decode(x), s, sec, cattrs, a.margin, a.vfloor, a.vweight) for s in check]
            res = pool.map(job_score, jobs, chunksize=1)
            falls = [(s, round(r[2], 1)) for s, r in zip(check, res) if r[1]]
            pk = [r[5] for r in res if not r[1] and r[5] is not None]
            out = {"check_n": len(check), "check_falls": len(falls), "check_rate": round(len(falls) / len(check), 4),
                   "check_score": round(float(np.mean([r[0] for r in res])), 2), "check_peak": round(float(np.mean(pk)), 3) if pk else None,
                   "check_fall_list": falls[:40]}
            write_params(os.path.join(HERE, f"{a.name}_g{gen}.txt"), rep, x, f"{a.name} incumbent at generation {gen}")
            return out
        c0 = check_eval(0)
        if c0:
            print(f"gen 0 CHECK incumbent: falls {c0['check_falls']}/{c0['check_n']} score {c0['check_score']} peak {c0['check_peak']}", flush=True)
            log.write(json.dumps({"gen": 0, **c0}) + "\n"); log.flush()
        gen = 0
        while gen < a.gens and (time.time() - t0) / 60.0 < a.max_minutes:
            gen += 1
            tg = time.time()
            nh = min(int(round(a.hard * a.k)), len(hard))
            hs = list(rng.choice(hard, nh, replace=False)) if nh else []
            rest = [s for s in pool_seeds if s not in set(hs)]
            A = [int(s) for s in hs] + [int(s) for s in rng.choice(rest, a.k - len(hs), replace=False)]
            # offspring: sparse Gaussian mutations of the incumbent
            X = [x.copy()]
            for _ in range(a.lam):
                mask = rng.random(rep.n) < q
                if not mask.any():
                    mask[rng.integers(rep.n)] = True
                X.append(np.clip(x + mask * sigma * rng.standard_normal(rep.n), 0.0, 1.0))
            X = np.array(X)
            S, F, T, PK = evaluate(pool, rep, X, A, a, a.margin)
            m = S.mean(axis=1)
            j = 1 + int(np.argmax(m[1:]))
            rec = {"gen": gen, "inc_A": round(float(m[0]), 2), "inc_fallsA": int(F[0].sum()), "best_A": round(float(m[j]), 2), "best_fallsA": int(F[j].sum()),
                   "med_A": round(float(np.median(m[1:])), 2), "sigma": round(sigma, 4)}
            # the hard list: seeds where the incumbent fell on this draw
            for s, f in zip(A, F[0]):
                if f and s not in hard:
                    hard.append(s)
            hard = hard[-400:]
            accepted = False
            if m[j] > m[0]:
                restB = [s for s in pool_seeds if s not in set(A)]
                B = [int(s) for s in rng.choice(restB, a.k2, replace=False)]
                SB, FB, TB, PKB = evaluate(pool, rep, np.array([x, X[j]]), B, a, a.margin)
                mb = SB.mean(axis=1)
                rec.update({"inc_B": round(float(mb[0]), 2), "inc_fallsB": int(FB[0].sum()), "best_B": round(float(mb[1]), 2), "best_fallsB": int(FB[1].sum())})
                if mb[1] > mb[0]:
                    accepted = True
                    x = X[j].copy()
                    n_acc += 1
                    since_acc = 0
                    write_params(bestp, rep, x, f"{a.name} incumbent after {n_acc} acceptances (generation {gen})")
            if not accepted:
                since_acc += 1
                if since_acc >= 10:
                    sigma = max(0.01, sigma * 0.9)
                    since_acc = 0
            rec.update({"accepted": accepted, "n_acc": n_acc, "gen_s": round(time.time() - tg, 1), "wall_min": round((time.time() - t0) / 60.0, 1)})
            if gen % a.check_every == 0:
                c = check_eval(gen)
                if c:
                    rec.update(c)
            log.write(json.dumps(rec) + "\n"); log.flush()
            print(" ".join(f"{k}={v}" for k, v in rec.items() if k != "check_fall_list"), flush=True)
    print("done", flush=True)


if __name__ == "__main__":
    main()
