"""hsearch: search.py's rollouts, representation and optimizers, driven by SUCCESSIVE-SEED PRUNING.

A candidate is scored by its worst rollout (risk 1.0: min over the training seeds). That makes the
seeds a cascade: a candidate whose first rollout already scores below the incumbent cannot beat it, so
its remaining seeds are never run. Each candidate runs its seeds in order inside one worker and stops at
the first score below the incumbent's (workers never wait for one another). With a fragile incumbent
(most offspring fall or slow down) that is 3-5x more generations per rollout than search.py.
A pruned candidate is told to the optimizer with its partial score (an upper bound of its true one).

Methods: `sep_cma` (search.SepCMA, restarted around the incumbent with a smaller step after `--stall`
generations without an improvement) and `es` ((1+lambda)-ES around the incumbent: every offspring
mutates a random subset of about `--mut` coordinates by N(0, sigma^2), sigma follows the success rate).

    python playground/hsearch.py sprint_touch_v4 --method es --budget 2400 --workers 4 --sigma 0.02 --seconds 30 \\
        --seeds 31,32,33,34,35,36 --attrs objective=2 --init params.txt --exclude drv_knee,... --out out.txt \\
        --log log.jsonl --archive arch.npz

The incumbent is written to --out at every improvement; --archive (npz) holds every candidate with its
score and the number of seeds it survived, for a validation pass on fresh seeds (scratchpad/sprint_knot/select.py).
"""

import argparse
import json
import math
import multiprocessing as mp
import os
import sys
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from search import BoxRep, SepCMA, describe, jsonable, parse_list, rollout, write_params  # noqa: E402
from practice import read_params  # noqa: E402


def cascade_job(job):
    """One candidate's cascade inside one worker: run the seeds in order, stop as soon as the running minimum is
    below `bar` (it can no longer beat the incumbent). A seed spec is (seed, gate_seconds): a plain seed runs the
    full horizon and its score enters the minimum; a GATE runs a short horizon (gate_seconds) and only counts if
    the candidate falls in it (then its low score is the candidate's score): a cheap screen for known hard starts.
    Returns (score, seeds run, metrics of the first full rollout).

    agg == "mean" (opt-in; `--agg mean`): the candidate's score is the MEAN of its seeds' scores, and a candidate stops
    (score = that rollout's score, far below any survivor's) at its first fall. A min over many seeds is a noisy
    statistic when every seed survives (the worst of 18 seeds moves by luck with every small mutation, so a sparse
    mutation of a good gait almost never passes); the mean moves smoothly and the fall rule keeps the robustness."""
    task, params, specs, seconds, attrs, bar = job[:6]
    agg = job[6] if len(job) > 6 else "min"
    score, first, ran = np.inf, None, 0
    total, count = 0.0, 0
    if agg == "meanall":
        # opt-in (`--agg meanall`, S4): the score is the mean over ALL the seeds, a fall costing its own (very low) score and NOT
        # stopping the candidate: a smooth statistic while most starts still fall (the number of survivors and how late the falls
        # come both move it), for a search that must climb out of a failing incumbent. A candidate stops early only when even a
        # perfect remaining set of seeds (each scoring HSEARCH_UB, default 350) could not lift its mean above `bar`; its returned
        # score is that upper bound (below the bar), like the pruned scores of the other modes. Gates are not used here.
        ub = float(os.environ.get("HSEARCH_UB", "350"))
        n = len(specs)
        for i, (seed, gate) in enumerate(specs):
            s, m, _ = rollout((task, params, seed, seconds) + ((attrs,) if attrs else ()))
            ran += 1
            total += s
            if first is None:
                first = m
            if total + (n - 1 - i) * ub < bar * n:
                return float((total + (n - 1 - i) * ub) / n), ran, first
        return float(total / n), ran, first
    for seed, gate in specs:
        s, m, _ = rollout((task, params, seed, gate or seconds) + ((attrs,) if attrs else ()))
        ran += 1
        if agg == "mean":
            if m.get("fell"):
                return float(s), ran, first if first is not None else m
            if not gate:
                total += s
                count += 1
                if first is None:
                    first = m
            continue
        if gate:
            if m.get("fell"):
                score = min(score, s)
        else:
            score = min(score, s)
            if first is None:
                first = m
        if score < bar:
            break
    if agg == "mean":
        return float(total / max(1, count)), ran, first
    return float(score), ran, first


class Cascade:
    def __init__(self, pool, rep, task, seeds, seconds, attrs, agg="min"):
        self.pool, self.rep, self.task, self.seeds, self.seconds, self.attrs = pool, rep, task, seeds, seconds, attrs
        self.agg = agg

    def evaluate(self, X, bar):
        """Scores (min over the seeds each candidate survived to), seeds run, rollouts used, metrics of the
        first seed. Each candidate runs its seeds in one worker and stops when its running minimum is < bar."""
        jobs = [(self.task, self.rep.decode(np.clip(x, 0, 1)), self.seeds, self.seconds, self.attrs, bar, self.agg) for x in X]
        res = self.pool.map(cascade_job, jobs, chunksize=1)
        score = np.array([r[0] for r in res])
        ran = np.array([r[1] for r in res])
        return score, ran, int(ran.sum()), [r[2] for r in res]


class ES:
    """(1+lambda)-ES around the incumbent with sparse mutations and a success-rate step size."""

    def __init__(self, x0, sigma0, seed, lam=24, mut=6, scales=None):
        self.x = np.asarray(x0, float).copy()
        self.n = len(self.x)
        self.sigma, self.lam, self.mut = sigma0, lam, mut
        self.rng = np.random.default_rng(seed)
        self.scales = np.ones(self.n) if scales is None else np.asarray(scales, float)
        self.hist = []
        self.pending = []  # candidates evaluated first next generation: a combination of several improving offspring
                           # (sparse mutations often touch different coordinates) and the extrapolation of the move

    def ask(self):
        q = min(1.0, self.mut / self.n)
        X = []
        for _ in range(self.lam):
            mask = self.rng.random(self.n) < q
            if not mask.any():
                mask[self.rng.integers(self.n)] = True
            X.append(np.clip(self.x + mask * self.sigma * self.scales * self.rng.standard_normal(self.n), 0, 1))
        for i, c in enumerate(self.pending[:len(X)]):
            X[i] = c
        self.pending = []
        return np.array(X)

    def tell(self, X, f, improved, improvers=()):
        if len(improvers) >= 2:  # try the improving moves all together
            self.pending.append(np.clip(self.x + sum(np.asarray(X[i], float) - self.x for i in improvers), 0, 1))
        if improved is not None:
            old = self.x
            self.x = np.asarray(X[improved], float).copy()
            self.pending.append(np.clip(self.x + (self.x - old), 0, 1))  # and one more step the same way
        self.hist.append(improved is not None)
        self.hist = self.hist[-8:]
        rate = sum(self.hist) / len(self.hist)
        self.sigma = float(np.clip(self.sigma * (1.15 if improved is not None else 0.93 if rate < 0.25 else 0.97), 0.002, 0.2))

    def info(self):
        return {"sigma": self.sigma, "rate": sum(self.hist) / max(1, len(self.hist))}


def save_archive(path, rep, seeds, X_all, F_all, R_all):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    np.savez_compressed(path + ".tmp.npz", X=np.array(X_all), F=np.array(F_all), ran=np.array(R_all), names=np.array(rep.names),
                        lo=rep.lo, hi=rep.hi, v0=rep.v0, x0=rep.x0, fixed=json.dumps(rep.fixed),
                        seeds=np.array([-1 if s[0] is None else s[0] for s in seeds]))
    os.replace(path + ".tmp.npz", path)


def main():
    ap = argparse.ArgumentParser(description="successive-seed pruning search")
    ap.add_argument("task")
    ap.add_argument("--method", default="es", choices=["es", "sep_cma"])
    ap.add_argument("--budget", type=int, default=2000, help="rollouts")
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--sigma", type=float, default=0.02)
    ap.add_argument("--lam", type=int, default=0, help="offspring per generation (es 24, sep_cma its default)")
    ap.add_argument("--mut", type=float, default=6.0, help="es: expected coordinates mutated per offspring")
    ap.add_argument("--stall", type=int, default=10, help="sep_cma: generations without an improvement before a restart")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--seeds", required=True, help="training seeds in cascade order (None = clean start)")
    ap.add_argument("--seconds", type=float, default=0)
    ap.add_argument("--init")
    ap.add_argument("--fixed")
    ap.add_argument("--only")
    ap.add_argument("--exclude")
    ap.add_argument("--attrs")
    ap.add_argument("--box")
    ap.add_argument("--agg", default="min", choices=["min", "mean", "meanall"], help="min: worst seed with pruning (default); mean: mean score, a candidate dies at its first fall; meanall: mean over all seeds, falls do not stop a candidate (HSEARCH_UB bounds the pruning)")
    ap.add_argument("--out", required=True)
    ap.add_argument("--log")
    ap.add_argument("--archive")
    a = ap.parse_args()
    fixed = {kv.split("=")[0]: float(kv.split("=")[1]) for kv in (a.fixed or "").split(",") if kv}
    init = read_params(a.init) if a.init else {}
    tun = describe(a.task, {**init, **fixed})
    if a.box:
        box = {kv.split("=")[0]: tuple(float(x) for x in kv.split("=")[1].split(":")) for kv in a.box.split(",")}
        unknown = sorted(set(box) - {t[0] for t in tun})
        if unknown:
            raise SystemExit(f"--box names no tunable: {', '.join(unknown)}")
        tun = [(t[0], t[1], *box.get(t[0], (t[2], t[3]))) for t in tun]
    rep = BoxRep.from_tunables(tun, parse_list(a.only), parse_list(a.exclude), init, fixed)
    # seeds: "31,32" or with gates "84g8,89g8,31,32" (a gate runs 8 s and counts only if the candidate falls)
    specs = []
    for tok in a.seeds.split(","):
        gate = None
        if "g" in tok:
            tok, g = tok.split("g")
            gate = float(g)
        specs.append((None if tok in ("None", "none") else int(tok), gate))
    seeds = specs
    attrs = {kv.split("=")[0]: float(kv.split("=")[1]) for kv in (a.attrs or "").split(",") if kv}
    print(f"hsearch {a.task}: {a.method}, {rep.n} tunables, budget {a.budget} rollouts, seeds {seeds}", flush=True)
    log = open(a.log, "w") if a.log else None
    t0 = time.time()
    X_all, F_all, R_all = [], [], []
    with mp.Pool(a.workers) as pool:
        cas = Cascade(pool, rep, a.task, seeds, a.seconds, attrs, a.agg)
        nfull = len(seeds)
        # the incumbent: the start, every seed
        s, ran, used, met = cas.evaluate(np.array([rep.x0]), -np.inf)
        best_f, best_x, best_m = float(s[0]), rep.x0.copy(), met[0]
        X_all.append(rep.x0.copy()); F_all.append(best_f); R_all.append(int(ran[0]))
        write_params(a.out, "hsearch", rep.decode(best_x), best_f, [best_m])
        print(f"start {best_f:.3f} ({used} rollouts)", flush=True)
        if a.method == "es":
            opt = ES(rep.x0, a.sigma, a.seed, lam=a.lam or 24, mut=a.mut)
        else:
            opt = SepCMA(rep.x0, sigma0=a.sigma, seed=a.seed, popsize=a.lam or None)
        gen, last_imp, restarts = 0, 0, 0
        while used < a.budget:
            gen += 1
            X = np.atleast_2d(opt.ask())
            X = np.clip(X, 0, 1)
            s, ran, u, met = cas.evaluate(X, best_f)
            used += u
            k = int(np.argmax(s))
            improved = k if s[k] > best_f and ran[k] == nfull else None
            improvers = [i for i in range(len(X)) if s[i] > best_f and ran[i] == nfull]
            if improved is not None:
                best_f, best_x, best_m = float(s[k]), X[k].copy(), met[k]
                write_params(a.out, "hsearch", rep.decode(best_x), best_f, [best_m])
                last_imp = gen
            for i in range(len(X)):
                X_all.append(X[i].copy()); F_all.append(float(s[i])); R_all.append(int(ran[i]))
            if a.method == "es":
                opt.tell(X, s, improved, improvers)
            else:
                opt.tell(X, s)
                if gen - last_imp >= a.stall:  # restart around the incumbent with a smaller step
                    restarts += 1
                    sig = max(0.003, opt.sigma * 0.6)
                    opt = SepCMA(best_x, sigma0=sig, seed=a.seed + restarts, popsize=a.lam or None)
                    last_imp = gen
            info = opt.info()
            print(f"gen {gen} used {used} best {best_f:.3f} gen_best {float(np.max(s)):.2f} alive_full {int((ran == nfull).sum())}/{len(X)} "
                  f"({time.time() - t0:.0f}s) {info}", flush=True)
            if a.archive and gen % 3 == 0:
                save_archive(a.archive, rep, seeds, X_all, F_all, R_all)
            if log:
                log.write(json.dumps(jsonable({"gen": gen, "used": used, "best": best_f, "gen_best": float(np.max(s)), "full": int((ran == nfull).sum()),
                                               "n": len(X), "wall": round(time.time() - t0, 1), "info": info})) + "\n")
                log.flush()
    if a.archive:
        save_archive(a.archive, rep, seeds, X_all, F_all, R_all)
    print("best", best_f, best_m)


if __name__ == "__main__":
    main()
