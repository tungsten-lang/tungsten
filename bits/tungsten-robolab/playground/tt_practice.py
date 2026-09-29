"""Practice on the fast path (round 10): sep-CMA over a few named parameters, common serves per generation.

    .venv-myo/bin/python playground/tt_practice.py --params P --controller C --names "z_bias:0.05,t_servo:0.1" \
        --pool fh --gens 12 --pop 10 --k 60 --held 120 --out params/x.txt --log out/tt_r10/x.log

`--names name:halfwidth,...` searches each name in [x0 - halfwidth, x0 + halfwidth] (x0 from the params file or its
default 0 when absent; use `--init name=v,...` to start elsewhere). Every generation draws `k` fresh serves from the
pool (`fh` / `bh` from out/tt_r10/pools_740000.json, `all` = 740000-741499 whatever their side), shared by all
candidates. Score per serve: solved + 0.4 (slack + 1.2) / 1.5, slack = the landing margin of the return (tt_impact.margin,
clipped to [-1.2, 0.3]; a miss scores -0.6 - its closest approach): a smooth stand-in that ranks like `solved` but with
much less noise. Every `--hold_every` generations the incumbent (mean of the distribution) is scored on the fixed held-out
serves (pool tail); the best held-out params are written to `--out`.
"""

import argparse
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import numpy as np  # noqa: E402

import search  # noqa: E402
import tt_fast  # noqa: E402
import tt_impact as ti  # noqa: E402


def serve_score(r):
    if "error" in r:
        return -1.0
    solved = 1.0 if r.get("solved", 0) > 0 else 0.0
    if r.get("hit") and r.get("ball_out_exact") and r.get("ball_pos_out"):
        sl = float(np.clip(ti.margin(r["ball_pos_out"], r["ball_out_exact"]), -1.2, 0.3))
    else:
        sl = float(np.clip(-0.6 - r.get("miss_dist", 0.5), -1.2, 0.3))
    return solved + 0.4 * (sl + 1.2) / 1.5


def write_params(path, params, header):
    with open(path, "w") as f:
        f.write(f"# {header}\n")
        for k in sorted(params):
            f.write(f"{k} {float(params[k])!r}\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--params", required=True)
    ap.add_argument("--controller", required=True)
    ap.add_argument("--names", required=True)
    ap.add_argument("--init", default="")
    ap.add_argument("--set", default="", help="fixed extra params name=value,...")
    ap.add_argument("--pool", default="all", choices=["fh", "bh", "all"])
    ap.add_argument("--pools_file", default=os.path.join(HERE, "..", "out", "tt_r10", "pools_740000.json"))
    ap.add_argument("--gens", type=int, default=12)
    ap.add_argument("--pop", type=int, default=10)
    ap.add_argument("--k", type=int, default=60)
    ap.add_argument("--sigma", type=float, default=0.2)
    ap.add_argument("--method", default="sep_cma")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--held", type=int, default=120)
    ap.add_argument("--hold_every", type=int, default=3)
    ap.add_argument("--workers", type=int, default=3)
    ap.add_argument("--out", required=True)
    ap.add_argument("--log")
    a = ap.parse_args()
    os.environ.setdefault("TT_ENV", "P2")
    params = tt_fast.read_params(a.params)
    for kv in filter(None, a.init.split(",")):
        k, v = kv.split("=")
        params[k] = float(v)
    for kv in filter(None, a.set.split(",")):
        k, v = kv.split("=")
        params[k] = float(v)
    names, half = [], []
    for kv in a.names.split(","):
        n, w = kv.split(":")
        names.append(n)
        half.append(float(w))
    x0v = np.array([params.get(n, 0.0) for n in names])
    lo, hi = x0v - np.array(half), x0v + np.array(half)
    rep = search.BoxRep(names, lo, hi, x0v, fixed={k: v for k, v in params.items() if k not in names})
    opt = search.make_optimizer(a.method, rep.x0, a.sigma, a.seed, **({"popsize": a.pop} if a.pop else {}))
    pools = json.load(open(a.pools_file))
    if a.pool == "all":
        seeds_all = list(range(740000, 741500))
    else:
        seeds_all = pools["fh" if a.pool == "fh" else "bh"]
    held = seeds_all[:a.held]
    train = seeds_all[a.held:]
    rng = np.random.default_rng(a.seed * 7919 + 3)
    ctl = os.path.abspath(a.controller)
    pool = tt_fast.pool(a.workers)
    log = open(a.log, "a") if a.log else None
    best = (-1e9, None)
    t0 = time.time()

    def held_score(x):
        p = rep.decode(np.clip(x, 0, 1))
        rows = pool.map(tt_fast.episode, [(dict(p), s, None, ctl) for s in held], chunksize=1)
        return float(np.mean([serve_score(r) for r in rows])), float(np.mean([r.get("solved", 0) for r in rows if "error" not in r])), p

    # the starting point's held-out score first
    sc0, sol0, p0 = held_score(rep.x0)
    print(json.dumps({"gen": 0, "held_score": round(sc0, 4), "held_solved": round(sol0, 4)}), flush=True)
    if log:
        log.write(json.dumps({"gen": 0, "held_score": sc0, "held_solved": sol0}) + "\n")
        log.flush()
    best = (sc0, p0)
    write_params(a.out, p0, f"tt_practice start ({a.params}); held-out {a.held} serves score {sc0:.3f} solved {sol0:.3f}")
    for g in range(a.gens):
        X = np.atleast_2d(opt.ask())
        seeds = [int(s) for s in rng.choice(train, a.k, replace=False)]
        jobs = [(dict(rep.decode(np.clip(x, 0, 1))), s, None, ctl) for x in X for s in seeds]
        rows = pool.map(tt_fast.episode, jobs, chunksize=1)
        scores, solved = [], []
        for i in range(len(X)):
            rs = rows[i * a.k:(i + 1) * a.k]
            scores.append(float(np.mean([serve_score(r) for r in rs])))
            solved.append(float(np.mean([r.get("solved", 0) for r in rs if "error" not in r])))
        opt.tell(X, scores, None)
        rec = {"gen": g + 1, "gen_best": round(max(scores), 4), "gen_median": round(float(np.median(scores)), 4),
               "gen_best_solved": round(solved[int(np.argmax(scores))], 4), "pop_solved": round(float(np.mean(solved)), 4),
               "wall_s": round(time.time() - t0)}
        if (g + 1) % a.hold_every == 0 or g + 1 == a.gens:
            x = getattr(opt, "mean", None)
            if x is None:
                x = X[int(np.argmax(scores))]
            hs, hsol, p = held_score(np.asarray(x))
            rec.update({"held_score": round(hs, 4), "held_solved": round(hsol, 4)})
            if hs > best[0]:
                best = (hs, p)
                write_params(a.out, p, f"tt_practice gen {g + 1} ({a.params}); held-out {a.held} serves score {hs:.3f} solved {hsol:.3f}")
        print(json.dumps(rec), flush=True)
        if log:
            log.write(json.dumps(rec) + "\n")
            log.flush()
    print("best held-out score", best[0])


if __name__ == "__main__":
    main()
