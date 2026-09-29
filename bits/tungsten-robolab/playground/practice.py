"""Practice: tune a skill's declared parameters with CMA-ES.

The skill declares tunables with `param(name, default, lo, hi)`; practice
asks the controller for that list (PARAM __describe), then searches the
box [lo, hi] (normalised to [0, 1]) with a standard (mu/mu_w, lambda)
CMA-ES, scoring each candidate with the task's `score(metrics)`. Rollouts
run in parallel worker processes, each with its own controller process.

    python playground/practice.py run --gens 60 --workers 6 --out params/run.txt

`--method` swaps the optimizer for any of playground/search.py's methods
(sep_cma, ipop, ga, oneplusone, random, cem, de, openai_es, nelder_mead,
pattern, bo, map_elites) under the same rollouts and scoring; `--budget`
caps the rollouts (default: gens x the CMA population). Plain `cma` without
`--budget` runs the original loop below, unchanged. playground/SEARCH.md
says which method to pick for which kind of problem.

    python playground/practice.py search_balance --method sep_cma --budget 600 --out params/b.txt
"""

import argparse
import importlib
import math
import multiprocessing as mp
import os
import sys
import time

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bridge import Sim as RobolabSim  # noqa: E402


def Sim(task, **kw):
    """The simulator for a task: MyoSuite bodies (tasks with env_id) or robolab's own.
    A task's `fixed_params` (e.g. a mode switch its skill reads) go to the
    controller under the caller's params."""
    fixed = getattr(task, "fixed_params", None)
    if fixed:
        kw["params"] = {**fixed, **(kw.get("params") or {})}
    if getattr(task, "env_id", None):
        from myo_bridge import MyoSim
        return MyoSim(task, **kw)
    return RobolabSim(task, **kw)


def load_task(name):
    return importlib.import_module(f"tasks.{name}").TASK()


def describe(task_name, fixed=None):
    """Tunables (name, default, lo, hi) as the skill declares them with the
    `fixed` params applied, so defaults that depend on other params resolve
    the same way they will during the search."""
    task = load_task(task_name)
    params = dict(fixed or {})
    params["__describe"] = 1
    sim = Sim(task, params=params)
    if hasattr(sim.task, "reset") and not getattr(task, "env_id", None):
        sim.task.reset(sim.m, sim.d)
    sim.start_controller()
    out = []
    for line in sim.proc.stdout:
        line = line.strip()
        if line == "END":
            break
        if line.startswith("TUNABLE"):
            _, name, default, lo, hi = line.split()
            out.append((name, float(default), float(lo), float(hi)))
    sim.stop_controller()
    seen, uniq = set(), []
    for t in out:
        if t[0] not in seen:
            seen.add(t[0])
            uniq.append(t)
    return uniq


def read_params(path):
    params = {}
    if path and os.path.exists(path):
        for line in open(path):
            parts = line.split()
            if len(parts) >= 2 and not line.startswith("#"):
                params[parts[0]] = float(parts[1])
    return params


def evaluate(job):
    task_name, params, seconds = job
    task = load_task(task_name)
    try:
        sim = Sim(task, params=params)
        metrics = sim.run(seconds)
        return task.score(metrics), metrics
    except Exception as e:  # a crashing candidate scores worst
        return -1e9, {"error": str(e)[:200]}


class CMA:
    def __init__(self, x0, sigma, popsize=None, seed=1):
        self.n = n = len(x0)
        self.rng = np.random.default_rng(seed)
        self.lam = popsize or 4 + int(3 * math.log(n))
        self.mu = self.lam // 2
        w = np.log(self.mu + 0.5) - np.log(np.arange(1, self.mu + 1))
        self.w = w / w.sum()
        self.mueff = 1 / np.sum(self.w ** 2)
        self.cc = (4 + self.mueff / n) / (n + 4 + 2 * self.mueff / n)
        self.cs = (self.mueff + 2) / (n + self.mueff + 5)
        self.c1 = 2 / ((n + 1.3) ** 2 + self.mueff)
        self.cmu = min(1 - self.c1, 2 * (self.mueff - 2 + 1 / self.mueff) / ((n + 2) ** 2 + self.mueff))
        self.damps = 1 + 2 * max(0, math.sqrt((self.mueff - 1) / (n + 1)) - 1) + self.cs
        self.chin = math.sqrt(n) * (1 - 1 / (4 * n) + 1 / (21 * n * n))
        self.mean = np.array(x0, float)
        self.sigma = sigma
        self.pc = np.zeros(n)
        self.ps = np.zeros(n)
        self.C = np.eye(n)
        self.B = np.eye(n)
        self.D = np.ones(n)
        self.gen = 0

    def ask(self):
        z = self.rng.standard_normal((self.lam, self.n))
        y = z @ (self.B * self.D).T
        return self.mean + self.sigma * y

    def tell(self, xs, scores):
        order = np.argsort(-np.asarray(scores))  # maximise
        xs = np.asarray(xs)[order]
        old = self.mean.copy()
        self.mean = self.w @ xs[:self.mu]
        y = (self.mean - old) / self.sigma
        Cinvsqrt = self.B @ np.diag(1 / self.D) @ self.B.T
        self.ps = (1 - self.cs) * self.ps + math.sqrt(self.cs * (2 - self.cs) * self.mueff) * Cinvsqrt @ y
        hs = np.linalg.norm(self.ps) / math.sqrt(1 - (1 - self.cs) ** (2 * (self.gen + 1))) < (1.4 + 2 / (self.n + 1)) * self.chin
        self.pc = (1 - self.cc) * self.pc + hs * math.sqrt(self.cc * (2 - self.cc) * self.mueff) * y
        ys = (xs[:self.mu] - old) / self.sigma
        self.C = ((1 - self.c1 - self.cmu) * self.C + self.c1 * (np.outer(self.pc, self.pc) + (1 - hs) * self.cc * (2 - self.cc) * self.C)
                  + self.cmu * (ys.T * self.w) @ ys)
        self.sigma *= math.exp((self.cs / self.damps) * (np.linalg.norm(self.ps) / self.chin - 1))
        self.C = np.triu(self.C) + np.triu(self.C, 1).T
        D2, self.B = np.linalg.eigh(self.C)
        self.D = np.sqrt(np.maximum(D2, 1e-20))
        self.gen += 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("task")
    ap.add_argument("--gens", type=int, default=40)
    ap.add_argument("--pop", type=int, default=0)
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--sigma", type=float, default=0.15)
    ap.add_argument("--seconds", type=float, default=0)
    ap.add_argument("--init", help="start from this params file (else declared defaults)")
    ap.add_argument("--out", required=True)
    ap.add_argument("--only", help="comma-separated tunables to search (others fixed)")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--method", default="cma", help="optimizer (see playground/search.py METHODS); default cma")
    ap.add_argument("--budget", type=int, default=0, help="rollout budget (default: gens x CMA population)")
    args = ap.parse_args()

    tun = describe(args.task, read_params(args.init))
    init = read_params(args.init)
    fixed = dict(init)
    if args.only:
        keep = set(args.only.split(","))
        tun = [t for t in tun if t[0] in keep]
    names = [t[0] for t in tun]
    lo = np.array([t[2] for t in tun])
    hi = np.array([t[3] for t in tun])
    x0 = np.array([(init.get(t[0], t[1]) - t[2]) / (t[3] - t[2]) for t in tun]).clip(0, 1)
    task = load_task(args.task)
    seconds = args.seconds or task.seconds
    print(f"practising {args.task}: {len(names)} tunables, {seconds}s rollouts", flush=True)

    def to_params(x):
        p = dict(fixed)
        p.update({n: float(l + (h - l) * v) for n, l, h, v in zip(names, lo, hi, np.clip(x, 0, 1))})
        return p

    if args.method != "cma" or args.budget:
        return practice_with(args, names, lo, hi, x0, fixed, seconds)
    es = CMA(x0, args.sigma, args.pop or None, seed=args.seed)
    best = (-1e18, None, None)
    base_score, base_m = evaluate((args.task, to_params(x0), seconds))
    best = (base_score, x0.copy(), base_m)
    print(f"gen 0 start score {base_score:.3f} {base_m}", flush=True)
    t0 = time.time()
    with mp.Pool(args.workers) as pool:
        for g in range(args.gens):
            xs = es.ask()
            jobs = [(args.task, to_params(x), seconds) for x in xs]
            res = pool.map(evaluate, jobs)
            scores = [r[0] for r in res]
            # penalise leaving the box so the search stays inside it
            pen = [s - 10.0 * float(np.sum(np.maximum(0, x - 1) + np.maximum(0, -x))) for s, x in zip(scores, xs)]
            es.tell(xs, pen)
            k = int(np.argmax(scores))
            if scores[k] > best[0]:
                best = (scores[k], np.clip(xs[k], 0, 1), res[k][1])
                write(args.out, args.task, to_params(best[1]), best[0], best[2])
            print(f"gen {g + 1} best {best[0]:.3f} gen-best {scores[k]:.3f} sigma {es.sigma:.3f} "
                  f"({time.time() - t0:.0f}s) {res[k][1]}", flush=True)
    write(args.out, args.task, to_params(best[1]), best[0], best[2])
    print("best", best[0], best[2])


def practice_with(args, names, lo, hi, x0, fixed, seconds):
    """Practice with a playground/search.py method under a rollout budget."""
    import search
    if args.method not in search.METHODS:
        raise SystemExit(f"unknown method {args.method!r}; one of {', '.join(sorted(search.METHODS))}")
    rep = search.BoxRep(names, lo, hi, lo + (hi - lo) * x0, fixed)
    prob = search.Problem(args.task, rep, [None], seconds)
    budget = args.budget or args.gens * (args.pop or 4 + int(3 * math.log(len(names))))
    opts = {"popsize": args.pop} if args.pop and args.method in ("sep_cma", "ipop", "ga", "cem", "de", "openai_es") else {}
    s = search.Search(prob, args.method, budget, seed=args.seed, sigma0=args.sigma, **opts)
    print(f"method {args.method}, budget {budget} rollouts", flush=True)
    t0 = time.time()
    last = [-1e18]

    def progress(s):
        if s.best[0] > last[0]:
            last[0] = s.best[0]
            write(args.out, args.task, s.params(), s.best[0], s.best[2][0])
        print(f"gen {s.gen} used {s.used} best {s.best[0]:.3f} ({time.time() - t0:.0f}s) "
              f"{s.opt.info() if s.opt else ''}", flush=True)

    with mp.Pool(args.workers) as pool:
        search.run_searches([s], pool, progress)
    write(args.out, args.task, s.params(), s.best[0], s.best[2][0])
    print("best", s.best[0], s.best[2][0])


def write(path, task, params, score, metrics):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w") as f:
        f.write(f"# robolab practice result for {task}: score {score:.4f}\n# metrics {metrics}\n")
        for k in sorted(params):
            if not k.startswith("__"):
                f.write(f"{k} {float(params[k])!r}\n")


if __name__ == "__main__":
    main()
