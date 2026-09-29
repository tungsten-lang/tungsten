"""search: derivative-free search methods for robolab skills.

A skill declares its tunables with `param(name, default, lo, hi)`; search
normalises them to the box [0, 1]^n and every method implements one ask/tell
interface (maximising):

    opt = make_optimizer("cma", x0, sigma0=0.15, seed=1)
    X = opt.ask()                 # candidates, one row each (rollouts clip to the box)
    opt.tell(X, scores, metrics)  # higher is better; metrics per row (MAP-Elites uses them)

A Search drives one optimizer on one Problem under a fixed rollout BUDGET:
x0 is evaluated first, each candidate costs k rollouts (one per training
seed, aggregated robustly as mean - risk * (mean - min), as in
robust_practice.py; or, with Problem(fresh=k), k new seeds every generation
shared by its candidates), the last batch is truncated so exactly BUDGET rollouts
are spent, every generation logs best-so-far against rollouts used, and the
best parameters are written at full precision (repr). run_searches() runs
several Searches in lockstep over one pool of worker processes, so the
sequential methods ((1+1)-ES, Nelder-Mead) keep every worker busy too.

Methods (METHODS):
    cma        CMA-ES, full covariance (practice.CMA), box penalty as practice.py
    sep_cma    separable (diagonal) CMA-ES, Ros & Hansen 2008
    ipop       CMA-ES with IPOP restarts (population doubles; restarts around
               the incumbent when sigma collapses or the run stalls)
    ga         real-coded GA: tournament selection, SBX crossover, polynomial
               mutation, elitism
    oneplusone (1+1)-ES random walk with the 1/5th success rule
    random     pure random search, uniform in the box
    cem        cross-entropy method, diagonal Gaussian, elite smoothing and
               decaying extra noise
    de         differential evolution rand/1/bin
    openai_es  antithetic natural-evolution strategy (OpenAI-ES): centred-rank
               fitness shaping, Adam on the mean, fixed sigma
    nelder_mead  Nelder-Mead with dimension-adaptive coefficients, restarts
    pattern    compass (coordinate pattern) search, full poll, step halving
    bo         Bayesian optimisation, TuRBO-style trust region: GP (Matern
               5/2, marginal-likelihood grid) + expected improvement, batch
               by kriging believer
    map_elites MAP-Elites (iso+line mutation) over a 2D behaviour descriptor
               from the task metrics (diverse skills; best elite reported)

Representations: BoxRep (a subset of the skill's tunables in their declared
box, the rest fixed) and SynergyRep (a few synergy coefficients mapped
linearly onto per-muscle contraction offsets, plus a BoxRep for the rest).

CLI:
    python playground/search.py search_jump --method cma --budget 1000 --workers 2 --out params/x.txt
    .venv-myo/bin/python playground/search.py search_balance --method sep_cma --seeds 1,2,3 --only k_ap,k_apv ...
"""

import argparse
import json
import math
import multiprocessing as mp
import os
import sys
import time

# One BLAS thread: the optimizers' linear algebra is small, and on a loaded machine
# a thread per core (OpenBLAS in the MyoSuite venv) made each GP fit take ~100 s.
for _v in ("OPENBLAS_NUM_THREADS", "OMP_NUM_THREADS", "MKL_NUM_THREADS", "VECLIB_MAXIMUM_THREADS"):
    os.environ.setdefault(_v, "1")

import numpy as np  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
from practice import CMA, Sim, load_task, read_params  # noqa: E402


# ---------------------------------------------------------------------------
# rollouts


def describe(task_name, fixed=None):
    """The skill's tunables [(name, default, lo, hi)] (practice.describe, but
    the handshake also carries the fixed params, e.g. a representation switch)."""
    task = load_task(task_name)
    sim = Sim(task, params={"__describe": 1, **(fixed or {})})
    if hasattr(sim.task, "reset") and not getattr(task, "env_id", None):
        sim.task.reset(sim.m, sim.d)
    sim.start_controller()
    out, seen = [], set()
    for line in sim.proc.stdout:
        line = line.strip()
        if line == "END":
            break
        if line.startswith("TUNABLE"):
            _, name, default, lo, hi = line.split()
            if name not in seen:
                seen.add(name)
                out.append((name, float(default), float(lo), float(hi)))
    sim.stop_controller()
    return out


def rollout(job):
    """One rollout: job = (task, params, seed, seconds[, task attribute
    overrides]). Returns (score, metrics, wall seconds). A crash scores -1e9."""
    task_name, params, seed, seconds = job[:4]
    task = load_task(task_name)
    for k, v in (job[4] if len(job) > 4 else {}).items():
        setattr(task, k, v)
    if seed is not None:
        task.seed = seed
    t0 = time.time()
    try:
        m = Sim(task, params=params).run(seconds or None)
        s = float(task.score(m))
    except Exception as e:  # a crashing candidate scores worst
        s, m = -1e9, {"error": str(e)[:300]}
    if not math.isfinite(s):
        s = -1e9
    return s, m, time.time() - t0


def jsonable(o):
    if isinstance(o, dict):
        return {str(k): jsonable(v) for k, v in o.items()}
    if isinstance(o, (list, tuple)):
        return [jsonable(v) for v in o]
    if isinstance(o, np.ndarray):
        return [jsonable(v) for v in o.tolist()]
    if isinstance(o, (np.bool_, bool)):
        return bool(o)
    if isinstance(o, (np.integer,)):
        return int(o)
    if isinstance(o, (np.floating, float)):
        return float(o) if math.isfinite(float(o)) else None
    return o


# ---------------------------------------------------------------------------
# representations


class BoxRep:
    """Tunables `names` searched in their declared boxes [lo, hi], normalised
    to [0, 1]; `fixed` params (the rest, and switches such as `rep`) ride along."""

    def __init__(self, names, lo, hi, x0, fixed=None):
        self.names = list(names)
        self.lo = np.asarray(lo, float)
        self.hi = np.asarray(hi, float)
        self.v0 = np.clip(np.asarray(x0, float), self.lo, self.hi)
        self.x0 = np.clip((self.v0 - self.lo) / (self.hi - self.lo), 0.0, 1.0)
        self.fixed = dict(fixed or {})
        self.n = len(self.names)

    @classmethod
    def from_tunables(cls, tunables, only=None, exclude=None, init=None, fixed=None):
        """Select tunables by name prefix (`only` / `exclude`: lists of names or
        prefixes ending in '*'); `init` (a params dict) overrides defaults and
        fixes every tunable that is not searched."""
        def match(name, pats):
            return any(name == p or (p.endswith("*") and name.startswith(p[:-1])) for p in pats)
        init = dict(init or {})
        keep = [t for t in tunables if (only is None or match(t[0], only)) and not (exclude and match(t[0], exclude))]
        names = [t[0] for t in keep]
        x0 = [init.get(t[0], t[1]) for t in keep]
        fx = dict(fixed or {})
        for k, v in init.items():
            if k not in names:
                fx[k] = v
        return cls(names, [t[2] for t in keep], [t[3] for t in keep], x0, fx)

    def decode(self, x):
        x = np.clip(np.asarray(x, float), 0.0, 1.0)
        v = self.lo + (self.hi - self.lo) * x
        # a coordinate still exactly at x0 decodes to its start value exactly
        # (lo + (hi - lo) x0 can be an ulp off, and a duration an ulp past a
        # control tick shifts a chunk boundary by a whole tick)
        v = np.where(x == self.x0, self.v0, v)
        p = dict(self.fixed)
        p.update({n: float(val) for n, val in zip(self.names, v)})
        return p


class SynergyRep:
    """A BoxRep for the ordinary tunables plus k synergy coefficients z that
    set many tunables through a basis: values = v0 + B z (clipped to each
    one's box; v0 = `origin`, zeros by default, e.g. offsets or a default
    keyframe series). z lives in [-zmax, zmax] per component; x0 has z = 0,
    so the start is the base motion exactly like the other representations."""

    def __init__(self, base, offset_names, basis, zmax, offset_lo, offset_hi, origin=None):
        self.base = base
        self.offset_names = list(offset_names)
        self.B = np.asarray(basis, float)  # (n_offsets, k)
        self.zmax = np.asarray(zmax, float)
        self.olo = np.asarray(offset_lo, float)
        self.ohi = np.asarray(offset_hi, float)
        self.origin = np.zeros(len(self.offset_names)) if origin is None else np.asarray(origin, float)
        self.k = self.B.shape[1]
        self.n = base.n + self.k
        self.names = base.names + [f"syn{i}" for i in range(self.k)]
        self.x0 = np.concatenate([base.x0, 0.5 * np.ones(self.k)])

    def offsets(self, x):
        z = (2.0 * np.clip(np.asarray(x, float)[self.base.n:], 0.0, 1.0) - 1.0) * self.zmax
        return np.clip(self.origin + self.B @ z, self.olo, self.ohi)

    def decode(self, x):
        p = self.base.decode(np.asarray(x, float)[:self.base.n])
        p.update({n: float(v) for n, v in zip(self.offset_names, self.offsets(x))})
        return p


class Problem:
    """What a Search optimises: a task, a representation, the training seeds
    (one rollout each per candidate; None = the task's clean start) and the
    robust aggregate mean - risk * (mean - min). `descriptor(metrics_list)`
    maps a candidate's rollouts to a point in [0, 1]^2 for MAP-Elites."""

    def __init__(self, task, rep, seeds=(None,), seconds=0.0, risk=0.5, descriptor=None, name=None, fresh=0,
                 attrs=None):
        self.task = task
        # task attribute overrides for every training rollout (e.g. the size
        # of a start perturbation); None leaves the jobs exactly as before
        self.attrs = dict(attrs) if attrs else None
        self.rep = rep
        self.seeds = list(seeds)
        # fresh > 0: every batch (generation) draws `fresh` new training seeds,
        # shared by all of its candidates (as robust_practice.py does), instead
        # of the fixed `seeds`: no fixed perturbation to overfit, at the price
        # of a noisy score (a batch's best may just have been lucky)
        self.fresh = int(fresh)
        self.k = self.fresh or len(self.seeds)
        self.seconds = seconds
        self.risk = risk
        self.descriptor = descriptor
        self.name = name or task

    def jobs(self, x, seeds=None):
        p = self.rep.decode(x)
        extra = (self.attrs,) if self.attrs else ()
        return [(self.task, p, s, self.seconds) + extra for s in (self.seeds if seeds is None else seeds)]

    def aggregate(self, results):
        sc = [r[0] for r in results]
        mean, mn = float(np.mean(sc)), float(np.min(sc))
        return (mean - self.risk * (mean - mn)) if len(sc) > 1 else sc[0]


# ---------------------------------------------------------------------------
# optimizers (maximise; candidates in normalised coordinates)


def box_penalty(X):
    X = np.atleast_2d(X)
    return 10.0 * np.sum(np.maximum(0.0, X - 1.0) + np.maximum(0.0, -X), axis=1)


class Optimizer:
    name = "base"

    def __init__(self, x0, sigma0=0.15, seed=1, f0=None, **opts):
        self.x0 = np.clip(np.asarray(x0, float), 0.0, 1.0)
        self.n = len(self.x0)
        self.sigma0 = sigma0
        self.rng = np.random.default_rng(seed)
        self.f0 = f0
        self.opts = opts

    def ask(self):
        raise NotImplementedError

    def tell(self, X, f, metrics=None):
        raise NotImplementedError

    def info(self):
        return {}


class CMAES(Optimizer):
    """Full-covariance CMA-ES: practice.CMA, out-of-box candidates penalised
    by 10 x their L1 distance from the box (as practice.py does)."""
    name = "cma"

    def __init__(self, x0, sigma0=0.15, seed=1, f0=None, popsize=None, **opts):
        super().__init__(x0, sigma0, seed, f0, **opts)
        self.es = CMA(self.x0, sigma0, popsize, seed=seed)

    def ask(self):
        return self.es.ask()

    def tell(self, X, f, metrics=None):
        self.es.tell(X, np.asarray(f, float) - box_penalty(X))

    def info(self):
        return {"sigma": float(self.es.sigma), "cond": float((self.es.D.max() / self.es.D.min()) ** 2), "lam": self.es.lam}


class SepCMA(Optimizer):
    """Separable CMA-ES (diagonal covariance; Ros & Hansen 2008): the rank-one
    and rank-mu learning rates are scaled up by (n + 2) / 3, so it adapts
    per-coordinate scales in O(n) and learns much faster than full CMA in
    high dimension, but ignores parameter correlations."""
    name = "sep_cma"

    def __init__(self, x0, sigma0=0.15, seed=1, f0=None, popsize=None, **opts):
        super().__init__(x0, sigma0, seed, f0, **opts)
        n = self.n
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
        self.mean = self.x0.copy()
        self.sigma = sigma0
        self.C = np.ones(n)
        self.pc = np.zeros(n)
        self.ps = np.zeros(n)
        self.gen = 0

    def ask(self):
        z = self.rng.standard_normal((self.lam, self.n))
        return self.mean + self.sigma * z * np.sqrt(self.C)

    def tell(self, X, f, metrics=None):
        f = np.asarray(f, float) - box_penalty(X)
        order = np.argsort(-f)
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

    def info(self):
        return {"sigma": float(self.sigma), "cond": float(self.C.max() / self.C.min())}


class IPOP(Optimizer):
    """CMA-ES with IPOP restarts (Auger & Hansen 2005): when the step size
    collapses (sigma * sqrt(max C) < tolx), the best score of the current run
    stalls for `stall` generations, or the population's scores are all equal,
    restart with twice the population. Restarts start around the incumbent
    (best-so-far) with the initial step size (`restart_from`="best"); "x0" and
    "random" (uniform in the box, the classic IPOP) are available."""
    name = "ipop"

    def __init__(self, x0, sigma0=0.15, seed=1, f0=None, popsize=None, restart_from="best", tolx=2e-3, stall=None, **opts):
        super().__init__(x0, sigma0, seed, f0, **opts)
        self.seed = seed
        self.restart_from = restart_from
        self.tolx = tolx
        self.stall_opt = stall
        self.best_x, self.best_f = self.x0.copy(), (f0 if f0 is not None else -np.inf)
        self.restarts = 0
        self._start(self.x0, popsize)

    def _start(self, mean, popsize):
        self.es = CMA(mean, self.sigma0, popsize, seed=self.seed + 1000 * self.restarts)
        self.run_best = -np.inf
        self.run_hist = []
        self.stall = self.stall_opt or max(12, 2 + int(6 * self.n / self.es.lam))

    def ask(self):
        return self.es.ask()

    def tell(self, X, f, metrics=None):
        f = np.asarray(f, float)
        self.es.tell(X, f - box_penalty(X))
        k = int(np.argmax(f))
        if f[k] > self.best_f:
            self.best_f, self.best_x = float(f[k]), np.clip(X[k], 0, 1)
        self.run_best = max(self.run_best, float(f[k]))
        self.run_hist.append(self.run_best)
        es = self.es
        collapsed = es.sigma * float(es.D.max()) < self.tolx
        stalled = len(self.run_hist) > self.stall and self.run_hist[-1] <= self.run_hist[-1 - self.stall] + 1e-9 * max(1.0, abs(self.run_hist[-1]))
        flat = float(np.max(f) - np.min(f)) < 1e-12
        if collapsed or stalled or flat:
            self.restarts += 1
            if self.restart_from == "random":
                mean = self.rng.uniform(0, 1, self.n)
            elif self.restart_from == "x0":
                mean = self.x0.copy()
            else:
                mean = self.best_x.copy()
            self._start(mean, 2 * es.lam)

    def info(self):
        return {"sigma": float(self.es.sigma), "lam": self.es.lam, "restarts": self.restarts}


class GA(Optimizer):
    """Real-coded generational GA with elitism: tournament selection (size
    `tour`), simulated binary crossover (Deb & Agrawal 1995; eta_c, prob pc),
    bounded polynomial mutation (eta_m, per-gene prob pm = 1/n), and the `elite`
    best carried over unchanged. The first population is x0 plus Gaussian
    perturbations of scale sigma0."""
    name = "ga"

    def __init__(self, x0, sigma0=0.15, seed=1, f0=None, popsize=None, elite=2, tour=3, pc=0.9, eta_c=15.0,
                 eta_m=20.0, pm=None, **opts):
        super().__init__(x0, sigma0, seed, f0, **opts)
        self.N = popsize or max(20, 2 * (4 + int(3 * math.log(self.n))))
        self.elite, self.tour, self.pc, self.eta_c, self.eta_m = elite, tour, pc, eta_c, eta_m
        self.pm = pm or 1.0 / self.n
        P = np.clip(self.x0 + sigma0 * self.rng.standard_normal((self.N, self.n)), 0, 1)
        P[0] = self.x0
        self.pending = P
        self.P, self.F = None, None
        self.gen = 0

    def _select(self):
        idx = self.rng.integers(0, len(self.P), self.tour)
        return self.P[idx[np.argmax(self.F[idx])]]

    def _sbx(self, a, b):
        c1, c2 = a.copy(), b.copy()
        if self.rng.uniform() > self.pc:
            return c1, c2
        for i in range(self.n):
            if self.rng.uniform() > 0.5 or abs(a[i] - b[i]) < 1e-14:
                continue
            y1, y2 = min(a[i], b[i]), max(a[i], b[i])
            u = self.rng.uniform()
            e = self.eta_c + 1.0
            # bounded SBX (Deb): spread limited by the distance to each bound
            beta = 1.0 + 2.0 * (y1 - 0.0) / (y2 - y1)
            alpha = 2.0 - beta ** -e
            bq = (u * alpha) ** (1 / e) if u <= 1 / alpha else (1 / (2 - u * alpha)) ** (1 / e)
            ch1 = 0.5 * ((y1 + y2) - bq * (y2 - y1))
            beta = 1.0 + 2.0 * (1.0 - y2) / (y2 - y1)
            alpha = 2.0 - beta ** -e
            bq = (u * alpha) ** (1 / e) if u <= 1 / alpha else (1 / (2 - u * alpha)) ** (1 / e)
            ch2 = 0.5 * ((y1 + y2) + bq * (y2 - y1))
            ch1, ch2 = min(max(ch1, 0.0), 1.0), min(max(ch2, 0.0), 1.0)
            if self.rng.uniform() < 0.5:
                ch1, ch2 = ch2, ch1
            c1[i], c2[i] = ch1, ch2
        return c1, c2

    def _mutate(self, x):
        x = x.copy()
        e = self.eta_m + 1.0
        for i in range(self.n):
            if self.rng.uniform() >= self.pm:
                continue
            y = x[i]
            d1, d2 = y, 1.0 - y
            u = self.rng.uniform()
            if u < 0.5:
                v = 2 * u + (1 - 2 * u) * (1 - d1) ** e
                dq = v ** (1 / e) - 1
            else:
                v = 2 * (1 - u) + 2 * (u - 0.5) * (1 - d2) ** e
                dq = 1 - v ** (1 / e)
            x[i] = min(max(y + dq, 0.0), 1.0)
        return x

    def ask(self):
        if self.pending is None:
            kids = []
            while len(kids) < self.N - self.elite:
                c1, c2 = self._sbx(self._select(), self._select())
                kids.append(self._mutate(c1))
                if len(kids) < self.N - self.elite:
                    kids.append(self._mutate(c2))
            self.pending = np.array(kids)
        return self.pending

    def tell(self, X, f, metrics=None):
        X, f = np.asarray(X), np.asarray(f, float)
        if self.P is None:
            self.P, self.F = X.copy(), f.copy()
        else:
            e = np.argsort(-self.F)[:self.elite]
            self.P = np.vstack([self.P[e], X])
            self.F = np.concatenate([self.F[e], f])
        self.pending = None
        self.gen += 1

    def info(self):
        return {"pop_spread": float(np.mean(np.std(self.P, axis=0))) if self.P is not None else None}


class GenOptimizer(Optimizer):
    """An optimizer written as a generator: `f = yield X` asks for the scores
    of the rows of X. Turns sequential algorithms into ask/tell."""

    def __init__(self, *a, **k):
        super().__init__(*a, **k)
        self._g = self.run()
        self._X = np.atleast_2d(next(self._g))
        self._metrics = None

    def ask(self):
        return self._X

    def tell(self, X, f, metrics=None):
        self._metrics = metrics
        self._X = np.atleast_2d(self._g.send(np.asarray(f, float)))

    def run(self):
        raise NotImplementedError

    def score0(self):
        """x0's score if the Search passed it (else evaluate it)."""
        if self.f0 is not None:
            return float(self.f0)
        return float((yield self.x0[None])[0])


class OnePlusOne(GenOptimizer):
    """(1+1)-ES, the adaptive random walk: one Gaussian step from the parent,
    kept if it is no worse; the step size follows the 1/5th success rule
    (Rechenberg; Kern et al. 2004: sigma *= exp((success - 1/5) / (4/5 d)),
    d = 1 + n/2)."""
    name = "oneplusone"

    def run(self):
        x = self.x0.copy()
        f = yield from self.score0()
        self.sigma = self.sigma0
        d = 1.0 + self.n / 2.0
        self.accepts = 0
        while True:
            y = np.clip(x + self.sigma * self.rng.standard_normal(self.n), 0, 1)
            fy = (yield y[None])[0]
            ok = fy >= f
            if ok:
                x, f = y, fy
                self.accepts += 1
            self.sigma *= math.exp((float(ok) - 0.2) / (0.8 * d))
            self.sigma = min(self.sigma, 1.0)

    def info(self):
        return {"sigma": float(getattr(self, "sigma", self.sigma0)), "accepts": getattr(self, "accepts", 0)}


class RandomSearch(Optimizer):
    """Pure random search: uniform samples in the box."""
    name = "random"

    def __init__(self, x0, sigma0=0.15, seed=1, f0=None, batch=10, **opts):
        super().__init__(x0, sigma0, seed, f0, **opts)
        self.batch = batch

    def ask(self):
        return self.rng.uniform(0, 1, (self.batch, self.n))

    def tell(self, X, f, metrics=None):
        pass


class CEM(Optimizer):
    """Cross-entropy method: a diagonal Gaussian refitted to the elite
    fraction each generation, smoothed (alpha) and with decaying extra noise
    (Szita & Lorincz 2006) so it does not collapse early."""
    name = "cem"

    def __init__(self, x0, sigma0=0.15, seed=1, f0=None, popsize=None, elite_frac=0.2, alpha=0.7, noise_gens=40, **opts):
        super().__init__(x0, sigma0, seed, f0, **opts)
        self.N = popsize or max(20, 2 * (4 + int(3 * math.log(self.n))))
        self.ne = max(2, int(round(elite_frac * self.N)))
        self.alpha, self.noise_gens = alpha, noise_gens
        self.mu = self.x0.copy()
        self.sd = sigma0 * np.ones(self.n)
        self.gen = 0

    def ask(self):
        return np.clip(self.mu + self.sd * self.rng.standard_normal((self.N, self.n)), 0, 1)

    def tell(self, X, f, metrics=None):
        e = np.asarray(X)[np.argsort(-np.asarray(f, float))[:self.ne]]
        a = self.alpha
        self.mu = a * e.mean(axis=0) + (1 - a) * self.mu
        extra = (0.25 * self.sigma0) ** 2 * max(0.0, 1.0 - self.gen / self.noise_gens)
        self.sd = np.sqrt(a * e.var(axis=0) + (1 - a) * self.sd ** 2 + extra)
        self.gen += 1

    def info(self):
        return {"sd": float(np.mean(self.sd))}


class DE(Optimizer):
    """Differential evolution, DE/rand/1/bin (Storn & Price 1997): trial
    u = x_r1 + F (x_r2 - x_r3) crossed binomially (CR) with its target, kept if
    no worse. Coordinates that leave the box go halfway back to the target."""
    name = "de"

    def __init__(self, x0, sigma0=0.15, seed=1, f0=None, popsize=None, F=0.6, CR=0.9, **opts):
        super().__init__(x0, sigma0, seed, f0, **opts)
        self.NP = popsize or 20
        self.F, self.CR = F, CR
        P = np.clip(self.x0 + sigma0 * self.rng.standard_normal((self.NP, self.n)), 0, 1)
        P[0] = self.x0
        self.P, self.fit = P, None
        self.gen = 0

    def ask(self):
        if self.fit is None:
            return self.P
        U = np.empty_like(self.P)
        for i in range(self.NP):
            r = self.rng.choice([j for j in range(self.NP) if j != i], 3, replace=False)
            v = self.P[r[0]] + self.F * (self.P[r[1]] - self.P[r[2]])
            cross = self.rng.uniform(size=self.n) < self.CR
            cross[self.rng.integers(self.n)] = True
            u = np.where(cross, v, self.P[i])
            lo, hi = u < 0, u > 1
            u[lo] = 0.5 * self.P[i][lo]
            u[hi] = 0.5 * (self.P[i][hi] + 1.0)
            U[i] = u
        self.trials = U
        return U

    def tell(self, X, f, metrics=None):
        f = np.asarray(f, float)
        if self.fit is None:
            self.fit = f.copy()
        else:
            better = f >= self.fit
            self.P[better] = np.asarray(X)[better]
            self.fit[better] = f[better]
        self.gen += 1

    def info(self):
        return {"pop_spread": float(np.mean(np.std(self.P, axis=0)))}


class OpenAIES(Optimizer):
    """Antithetic natural-evolution strategy (Salimans et al. 2017): m mirrored
    pairs mean +- sigma eps, centred-rank fitness shaping, the gradient
    estimate sum (r+ - r-) eps / (2 m sigma) followed with Adam. sigma is
    fixed (0.7 sigma0); the best sample is the reported solution."""
    name = "openai_es"

    def __init__(self, x0, sigma0=0.15, seed=1, f0=None, popsize=None, lr=None, sigma=None, **opts):
        super().__init__(x0, sigma0, seed, f0, **opts)
        lam = popsize or 4 + int(3 * math.log(self.n))
        self.m = max(2, lam // 2)
        self.sigma = sigma or 0.7 * sigma0
        self.lr = lr or 0.15 * sigma0
        self.theta = self.x0.copy()
        self.mo, self.v, self.t = np.zeros(self.n), np.zeros(self.n), 0

    def ask(self):
        self.eps = self.rng.standard_normal((self.m, self.n))
        return np.vstack([self.theta + self.sigma * self.eps, self.theta - self.sigma * self.eps])

    def tell(self, X, f, metrics=None):
        f = np.asarray(f, float)
        ranks = np.empty(len(f))
        ranks[np.argsort(f)] = np.arange(len(f))
        u = ranks / (len(f) - 1) - 0.5
        g = ((u[:self.m] - u[self.m:]) @ self.eps) / (2 * self.m * self.sigma)
        self.t += 1
        b1, b2 = 0.9, 0.999
        self.mo = b1 * self.mo + (1 - b1) * g
        self.v = b2 * self.v + (1 - b2) * g * g
        mh, vh = self.mo / (1 - b1 ** self.t), self.v / (1 - b2 ** self.t)
        self.theta = np.clip(self.theta + self.lr * mh / (np.sqrt(vh) + 1e-8), 0, 1)

    def info(self):
        return {"theta_step": float(self.lr)}


class NelderMead(GenOptimizer):
    """Nelder-Mead simplex (maximising) with the dimension-adaptive
    coefficients of Gao & Han 2012; the initial simplex is x0 plus sigma0 along
    each axis. When the simplex collapses below 1e-3 it restarts around the
    best vertex."""
    name = "nelder_mead"

    def run(self):
        n = self.n
        a, b, g, s = 1.0, 1.0 + 2.0 / n, 0.75 - 1.0 / (2 * n), 1.0 - 1.0 / n
        f0 = yield from self.score0()
        x_best, f_best = self.x0.copy(), f0
        scale = self.sigma0
        self.restarts = 0
        while True:
            S = [x_best.copy()]
            for i in range(n):
                v = x_best.copy()
                v[i] = v[i] + scale if v[i] + scale <= 1.0 else v[i] - scale
                S.append(v)
            S = np.array(S)
            F = np.empty(n + 1)
            F[0] = f_best
            F[1:] = yield S[1:]
            while True:
                o = np.argsort(-F)
                S, F = S[o], F[o]
                if F[0] > f_best:
                    x_best, f_best = S[0].copy(), F[0]
                if np.max(np.abs(S - S[0])) < 1e-3:
                    break
                c = S[:-1].mean(axis=0)
                xr = np.clip(c + a * (c - S[-1]), 0, 1)
                fr = (yield xr[None])[0]
                if fr > F[0]:
                    xe = np.clip(c + b * (xr - c), 0, 1)
                    fe = (yield xe[None])[0]
                    S[-1], F[-1] = (xe, fe) if fe > fr else (xr, fr)
                elif fr > F[-2]:
                    S[-1], F[-1] = xr, fr
                else:
                    if fr > F[-1]:
                        xc = np.clip(c + g * (xr - c), 0, 1)
                        fc = (yield xc[None])[0]
                        ok = fc >= fr
                    else:
                        xc = np.clip(c - g * (c - S[-1]), 0, 1)
                        fc = (yield xc[None])[0]
                        ok = fc > F[-1]
                    if ok:
                        S[-1], F[-1] = xc, fc
                    else:
                        S[1:] = S[0] + s * (S[1:] - S[0])
                        F[1:] = yield S[1:]
            self.restarts += 1
            scale = max(0.02, 0.5 * scale)

    def info(self):
        return {"restarts": getattr(self, "restarts", 0)}


class PatternSearch(GenOptimizer):
    """Compass search (a coordinate pattern search): poll x +- step along every
    axis in one batch, move to the best poll point if it improves and double
    the step, else halve it; restart the step at sigma0 once it falls below
    1e-3."""
    name = "pattern"

    def run(self):
        x = self.x0.copy()
        f = yield from self.score0()
        self.step = self.sigma0
        while True:
            P = np.vstack([np.clip(x + self.step * e, 0, 1) for e in np.vstack([np.eye(self.n), -np.eye(self.n)])])
            FP = yield P
            k = int(np.argmax(FP))
            if FP[k] > f:
                x, f = P[k], FP[k]
                self.step = min(0.5, 2.0 * self.step)
            else:
                self.step *= 0.5
                if self.step < 1e-3:
                    self.step = self.sigma0

    def info(self):
        return {"step": float(getattr(self, "step", self.sigma0))}


def _matern52(A, B, ell):
    d = np.sqrt(np.maximum(((A[:, None, :] - B[None, :, :]) ** 2).sum(-1), 0.0)) / ell
    s5 = math.sqrt(5.0)
    return (1 + s5 * d + 5.0 / 3.0 * d * d) * np.exp(-s5 * d)


def _norm_pdf(z):
    return np.exp(-0.5 * z * z) / math.sqrt(2 * math.pi)


def _norm_cdf(z):
    from math import erf
    return 0.5 * (1 + np.vectorize(erf)(z / math.sqrt(2)))


class BO(GenOptimizer):
    """Bayesian optimisation in a trust region (TuRBO-1 style, Eriksson et al.
    2019): a GP with a Matern-5/2 kernel on standardised scores, its
    lengthscale and noise picked by marginal likelihood on a grid, fitted to
    the points nearest the incumbent; candidates are perturbations of the
    incumbent inside a box of side L (each coordinate perturbed with
    probability min(1, 20/n)), scored by expected improvement; `q` points per
    batch by kriging believer. L doubles after 3 successes, halves after
    max(4, n/q) failures, and resets when it falls below 1/128. The first
    `n_init` points are Gaussian perturbations of x0 (scale sigma0)."""
    name = "bo"

    def __init__(self, x0, sigma0=0.15, seed=1, f0=None, q=2, n_init=None, max_points=300, n_cand=2000, **opts):
        self.q, self.n_init_opt, self.max_points, self.n_cand = q, n_init, max_points, n_cand
        super().__init__(x0, sigma0, seed, f0, **opts)

    def _fit(self, X, y):
        mu, sd = y.mean(), y.std() + 1e-12
        z = (y - mu) / sd
        best = None
        for ell in (0.05, 0.1, 0.2, 0.35, 0.6, 1.0, 1.7, 3.0):
            ell = ell * math.sqrt(self.n) / 3.0
            K0 = _matern52(X, X, ell)
            for noise in (1e-6, 1e-3, 1e-2, 1e-1):
                K = K0 + noise * np.eye(len(X))
                try:
                    Lc = np.linalg.cholesky(K)
                except np.linalg.LinAlgError:
                    continue
                al = np.linalg.solve(Lc.T, np.linalg.solve(Lc, z))
                ll = -0.5 * z @ al - np.sum(np.log(np.diag(Lc)))
                if best is None or ll > best[0]:
                    best = (ll, ell, noise, Lc, al)
        _, ell, noise, Lc, al = best
        return {"X": X, "z": z, "mu": mu, "sd": sd, "ell": ell, "noise": noise, "L": Lc, "al": al}

    def _predict(self, gp, C):
        Ks = _matern52(C, gp["X"], gp["ell"])
        m = Ks @ gp["al"]
        v = np.linalg.solve(gp["L"], Ks.T)
        var = np.maximum(1.0 - np.sum(v * v, axis=0), 1e-12)
        return m, np.sqrt(var)

    def run(self):
        n = self.n
        f0 = yield from self.score0()
        X = [self.x0.copy()]
        Y = [f0]
        n_init = self.n_init_opt or min(max(10, n), 40)
        P = np.clip(self.x0 + self.sigma0 * self.rng.standard_normal((n_init, n)), 0, 1)
        X += list(P)
        Y += list((yield P))
        self.L = L0 = 0.8
        succ = fail = 0
        fail_tol = max(4, int(math.ceil(n / self.q)))
        prob = min(1.0, 20.0 / n)
        while True:
            Xa, Ya = np.array(X), np.array(Y, float)
            k = int(np.argmax(Ya))
            center, fbest = Xa[k], Ya[k]
            if len(Xa) > self.max_points:
                near = np.argsort(np.sum((Xa - center) ** 2, axis=1))[:self.max_points]
                Xa, Ya = Xa[near], Ya[near]
            gp = self._fit(Xa, Ya)
            lo = np.clip(center - self.L / 2, 0, 1)
            hi = np.clip(center + self.L / 2, 0, 1)
            C = np.tile(center, (self.n_cand, 1))
            mask = self.rng.uniform(size=(self.n_cand, n)) < prob
            mask[np.arange(self.n_cand), self.rng.integers(0, n, self.n_cand)] = True
            R = lo + (hi - lo) * self.rng.uniform(size=(self.n_cand, n))
            C[mask] = R[mask]
            batch = []
            zbest = (fbest - gp["mu"]) / gp["sd"]
            for _ in range(self.q):
                m, s = self._predict(gp, C)
                imp = m - zbest
                zz = imp / s
                ei = imp * _norm_cdf(zz) + s * _norm_pdf(zz)
                j = int(np.argmax(ei))
                batch.append(C[j].copy())
                # kriging believer: pretend the GP mean was observed there
                Xa = np.vstack([gp["X"], C[j]])
                Ya = np.concatenate([gp["z"] * gp["sd"] + gp["mu"], [m[j] * gp["sd"] + gp["mu"]]])
                C = np.delete(C, j, axis=0)
                gp = self._fit(Xa, Ya) if len(batch) < self.q else gp
            B = np.array(batch)
            FB = yield B
            X += list(B)
            Y += list(FB)
            if np.max(FB) > fbest + 1e-3 * abs(fbest):
                succ, fail = succ + 1, 0
            else:
                succ, fail = 0, fail + 1
            if succ >= 3:
                self.L, succ = min(1.6, 2 * self.L), 0
            elif fail >= fail_tol:
                self.L, fail = self.L / 2, 0
            if self.L < 1.0 / 128:
                self.L = L0

    def info(self):
        return {"L": float(getattr(self, "L", 0.8))}


class MAPElites(Optimizer):
    """MAP-Elites (Mouret & Clune 2015) with iso+line mutation (Vassiliades &
    Mouret 2018): an archive keeps the best candidate per cell of a `res` x
    `res` grid over a 2D behaviour descriptor in [0, 1]^2 (Problem.descriptor
    of the candidate's metrics); each batch mutates uniformly chosen elites:
    x_i + sigma_iso N(0, I) + sigma_line (x_j - x_i) N(0, 1). The best elite is
    the reported solution; coverage and QD score show the diversity."""
    name = "map_elites"

    def __init__(self, x0, sigma0=0.15, seed=1, f0=None, batch=16, res=10, iso=None, line=0.3, descriptor=None, **opts):
        super().__init__(x0, sigma0, seed, f0, **opts)
        self.batch, self.res = batch, res
        self.iso, self.line = iso or 0.5 * sigma0, line
        self.descriptor = descriptor
        self.archive = {}  # cell -> (f, x, descriptor)

    def ask(self):
        if len(self.archive) < 2:
            X = np.clip(self.x0 + self.sigma0 * self.rng.standard_normal((self.batch, self.n)), 0, 1)
            if not self.archive:
                X[0] = self.x0
            return X
        keys = list(self.archive)
        out = []
        for _ in range(self.batch):
            a = self.archive[keys[self.rng.integers(len(keys))]][1]
            b = self.archive[keys[self.rng.integers(len(keys))]][1]
            y = a + self.iso * self.rng.standard_normal(self.n) + self.line * (b - a) * self.rng.standard_normal()
            out.append(np.clip(y, 0, 1))
        return np.array(out)

    def tell(self, X, f, metrics=None):
        for i, (x, s) in enumerate(zip(np.asarray(X), np.asarray(f, float))):
            if s <= -1e8:
                continue
            if self.descriptor is not None and metrics is not None:
                d = np.clip(np.asarray(self.descriptor(metrics[i]), float), 0, 0.999999)
            else:
                d = np.clip(x[:2], 0, 0.999999)
            cell = tuple((d * self.res).astype(int))
            if cell not in self.archive or s > self.archive[cell][0]:
                self.archive[cell] = (float(s), np.clip(x, 0, 1), d.tolist())

    def info(self):
        fs = [v[0] for v in self.archive.values()]
        return {"cells": len(self.archive), "coverage": len(self.archive) / self.res ** 2,
                "qd": float(np.sum(np.array(fs) - min(fs))) if fs else 0.0}


METHODS = {c.name: c for c in (CMAES, SepCMA, IPOP, GA, OnePlusOne, RandomSearch, CEM, DE, OpenAIES, NelderMead,
                               PatternSearch, BO, MAPElites)}


def make_optimizer(method, x0, sigma0=0.15, seed=1, f0=None, **opts):
    if method not in METHODS:
        raise SystemExit(f"unknown method {method!r}; one of {', '.join(METHODS)}")
    return METHODS[method](x0, sigma0=sigma0, seed=seed, f0=f0, **opts)


# ---------------------------------------------------------------------------
# a search under a rollout budget


class Search:
    """One optimizer on one Problem with a rollout budget. Drive it with
    run_searches (or .run(pool)). Writes, when paths are given: `out` the best
    params (full precision), `log` one JSON line per generation, `archive`
    (.npz) every evaluated candidate and its score."""

    def __init__(self, problem, method, budget, seed=1, sigma0=0.15, out=None, log=None, archive=None, label=None,
                 **opts):
        self.problem, self.method, self.budget, self.seed = problem, method, int(budget), seed
        self.sigma0, self.opts = sigma0, opts
        self.out, self.log_path, self.archive_path = out, log, archive
        self.label = label or f"{problem.name}/{method}/s{seed}"
        self.used = 0
        self.gen = 0
        self.best = (-np.inf, problem.rep.x0.copy(), None)
        self.curve = []  # (rollouts used, best-so-far)
        self.X, self.F = [], []
        self.opt = None
        self.done = False
        self.t0 = None
        self.rollout_s = 0.0
        self.opt_s = 0.0
        self._pending = None
        if self.log_path:
            os.makedirs(os.path.dirname(self.log_path) or ".", exist_ok=True)
            open(self.log_path, "w").close()

    # -- batching ------------------------------------------------------------

    def next_jobs(self):
        """Jobs for the next batch, or [] when the budget is spent."""
        if self.done:
            return []
        if self.t0 is None:
            self.t0 = time.time()
        k = self.problem.k
        if self.opt is None:
            X = self.problem.rep.x0[None]
        else:
            t = time.time()
            X = np.atleast_2d(self.opt.ask())
            self.opt_s += time.time() - t
        room = (self.budget - self.used) // k
        if room <= 0:
            self.done = True
            return []
        self.truncated = len(X) > room
        X = X[:room]
        self._pending = X
        seeds = None
        if self.problem.fresh:
            if not hasattr(self, "_seed_rng"):
                self._seed_rng = np.random.default_rng(10007 * self.seed + 17)
            seeds = [int(v) for v in self._seed_rng.integers(1000, 10 ** 6, self.problem.fresh)]
        return [j for x in X for j in self.problem.jobs(np.clip(x, 0, 1), seeds)]

    def consume(self, results):
        X, k = self._pending, self.problem.k
        scores, metrics = [], []
        for i in range(len(X)):
            r = results[i * k:(i + 1) * k]
            scores.append(self.problem.aggregate(r))
            metrics.append([m for _, m, _ in r])
            self.rollout_s += sum(w for _, _, w in r)
        self.used += len(X) * k
        for x, s in zip(X, scores):
            self.X.append(np.clip(x, 0, 1))
            self.F.append(s)
        j = int(np.argmax(scores))
        if scores[j] > self.best[0]:
            self.best = (float(scores[j]), np.clip(X[j], 0, 1), metrics[j])
            self.write_best()
        self.curve.append((self.used, self.best[0]))
        if self.opt is None:
            self.opt = make_optimizer(self.method, self.problem.rep.x0, self.sigma0, self.seed, f0=scores[0],
                                      descriptor=self.problem.descriptor, **self.opts)
        elif not self.truncated:
            t = time.time()
            self.opt.tell(X, scores, metrics)
            self.opt_s += time.time() - t
        self.gen += 1
        if self.log_path:
            row = {"gen": self.gen, "used": self.used, "best": self.best[0], "gen_best": float(np.max(scores)),
                   "gen_median": float(np.median(scores)), "n": len(X), "wall": round(time.time() - self.t0, 2),
                   "rollout_s": round(self.rollout_s, 2), "info": self.opt.info() if self.opt else {}}
            with open(self.log_path, "a") as f:
                f.write(json.dumps(jsonable(row)) + "\n")
        if self.used + k > self.budget:
            self.done = True
            self.finish()

    def params(self, x=None):
        return self.problem.rep.decode(self.best[1] if x is None else x)

    def write_best(self):
        if self.out:
            write_params(self.out, self.label, self.params(), self.best[0], self.best[2])

    def finish(self):
        self.write_best()
        if self.archive_path:
            os.makedirs(os.path.dirname(self.archive_path) or ".", exist_ok=True)
            np.savez_compressed(self.archive_path, X=np.array(self.X), F=np.array(self.F),
                                names=np.array(self.problem.rep.names), curve=np.array(self.curve))

    def summary(self):
        return {"label": self.label, "method": self.method, "seed": self.seed, "budget": self.budget, "used": self.used,
                "best": self.best[0], "curve": self.curve, "wall": round(time.time() - (self.t0 or time.time()), 1),
                "rollout_s": round(self.rollout_s, 1), "opt_s": round(self.opt_s, 2),
                "params": self.params(), "metrics": self.best[2], "info": self.opt.info() if self.opt else {}}


def write_params(path, label, params, score, metrics):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w") as f:
        f.write(f"# robolab search result {label}: score {score:.6f}\n")
        f.write(f"# metrics {json.dumps(jsonable(metrics))[:4000]}\n")
        for k in sorted(params):
            if not k.startswith("__"):
                f.write(f"{k} {float(params[k])!r}\n")


def run_searches(searches, pool, progress=None):
    """Run Searches in lockstep: each round takes every unfinished search's
    next batch, evaluates all rollouts on the pool, and hands results back."""
    active = list(searches)
    while active:
        batches = [(s, s.next_jobs()) for s in active]
        batches = [(s, j) for s, j in batches if j]
        if not batches:
            break
        flat = [j for _, j in batches for j in j]
        res = pool.map(rollout, flat, chunksize=1)
        i = 0
        for s, jobs in batches:
            s.consume(res[i:i + len(jobs)])
            i += len(jobs)
            if progress:
                progress(s)
        active = [s for s in active if not s.done]
    return searches


def evaluate_params(pool, task, params, seeds, seconds=0.0, attrs=None):
    """Held-out evaluation: one rollout per seed. Returns (scores, metrics)."""
    res = pool.map(rollout, [(task, params, s, seconds, attrs or {}) for s in seeds], chunksize=1)
    return [r[0] for r in res], [r[1] for r in res]


# ---------------------------------------------------------------------------
# CLI


def parse_list(s, cast=str):
    if s is None:
        return None
    return [cast(v) if v not in ("None", "none", "") else None for v in s.split(",")]


def main():
    ap = argparse.ArgumentParser(description="Search a robolab skill's tunables with a chosen method")
    ap.add_argument("task")
    ap.add_argument("--method", default="cma", choices=sorted(METHODS))
    ap.add_argument("--budget", type=int, default=1000, help="rollouts (a candidate costs one per training seed)")
    ap.add_argument("--workers", type=int, default=2)
    ap.add_argument("--sigma", type=float, default=0.15, help="initial step size in the normalised box")
    ap.add_argument("--pop", type=int, default=0)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--seeds", help="training seeds, comma-separated (None = the clean start); default: None")
    ap.add_argument("--risk", type=float, default=0.5)
    ap.add_argument("--seconds", type=float, default=0)
    ap.add_argument("--init", help="start from this params file (else declared defaults); its non-searched values are fixed")
    ap.add_argument("--fixed", help="extra fixed params name=value,... (e.g. rep=0)")
    ap.add_argument("--only", help="tunables to search (names, or prefixes ending in *)")
    ap.add_argument("--exclude")
    ap.add_argument("--attrs", help="task attribute overrides for training rollouts, name=value,... (e.g. noise=0.001)")
    ap.add_argument("--box", help="widen or move tunables' search boxes, name=lo:hi,... (a skill does not clamp a params-file value; "
                                  "only the search's box does)")
    ap.add_argument("--out", required=True)
    ap.add_argument("--log")
    a = ap.parse_args()
    fixed = {}
    if a.fixed:
        for kv in a.fixed.split(","):
            k, v = kv.split("=")
            fixed[k] = float(v)
    init = read_params(a.init)
    tun = describe(a.task, {**init, **fixed})
    if a.box:
        box = {kv.split("=")[0]: tuple(float(x) for x in kv.split("=")[1].split(":")) for kv in a.box.split(",")}
        unknown = sorted(set(box) - {t[0] for t in tun})
        if unknown:
            raise SystemExit(f"--box names no tunable: {', '.join(unknown)}")
        tun = [(t[0], t[1], *box.get(t[0], (t[2], t[3]))) for t in tun]
    rep = BoxRep.from_tunables(tun, parse_list(a.only), parse_list(a.exclude), init, fixed)
    seeds = parse_list(a.seeds, int) or [None]
    attrs = {kv.split("=")[0]: float(kv.split("=")[1]) for kv in (a.attrs or "").split(",") if kv}
    prob = Problem(a.task, rep, seeds, a.seconds, a.risk, attrs=attrs)
    opts = {"popsize": a.pop} if a.pop and a.method in ("cma", "sep_cma", "ipop", "ga", "cem", "de", "openai_es") else {}
    s = Search(prob, a.method, a.budget, a.seed, a.sigma, out=a.out, log=a.log, **opts)
    print(f"search {a.task}: {a.method}, {rep.n} tunables, budget {a.budget} rollouts, seeds {seeds}", flush=True)

    def progress(s):
        print(f"gen {s.gen} used {s.used} best {s.best[0]:.4f} ({time.time() - s.t0:.0f}s) {s.opt.info() if s.opt else ''}",
              flush=True)

    with mp.Pool(a.workers) as pool:
        run_searches([s], pool, progress)
    print("best", s.best[0], s.best[2])


if __name__ == "__main__":
    main()
