"""Robust practice for the run skill: CMA-ES (playground/practice.py's CMA,
unchanged) where each candidate is scored over several rollouts: the clean
standing start plus `--k - 1` starts with a perturbed initial pose (fresh
seeds every generation, shared by all candidates of that generation).
Aggregate = mean - `--risk` * (mean - min). Params are written at full
precision (repr), so the file reproduces exactly what was scored (the
bridge sends every param at 9 significant digits either way).

usage: robust_practice.py --out p.txt [--task run] [--init p0.txt] [--gens 60] [--k 3] ...
"""
import argparse, math, multiprocessing as mp, os, sys, time
import numpy as np
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "playground"))
os.chdir(ROOT)
from practice import CMA, describe, read_params, write, load_task  # noqa
from practice import Sim  # noqa


CAP = float(os.environ.get("RUN_SPEED_CAP", "0"))


def evaluate(job):
    task_name, params, seed, seconds = job
    task = load_task(task_name)
    task.seed = seed
    if CAP:
        task.speed_cap = CAP
    try:
        m = Sim(task, params=params).run(seconds)
        return task.score(m), m
    except Exception as e:
        return -1e9, {"error": str(e)[:200]}


def write_full(path, task, params, score, metrics):
    """practice.write, but at full precision (repr round-trips exactly)."""
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w") as f:
        f.write(f"# robolab robust practice result for {task}: score {score:.4f}\n# metrics {metrics}\n")
        for k in sorted(params):
            if not k.startswith("__"):
                f.write(f"{k} {float(params[k])!r}\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--task", default="run", help="task module (run, run_lean, run_bound, ...)")
    ap.add_argument("--gens", type=int, default=60)
    ap.add_argument("--pop", type=int, default=0)
    ap.add_argument("--workers", type=int, default=3)
    ap.add_argument("--sigma", type=float, default=0.08)
    ap.add_argument("--seconds", type=float, default=14)
    ap.add_argument("--k", type=int, default=3)
    ap.add_argument("--long", type=float, default=0, help="seconds for the clean rollout (default: --seconds)")
    ap.add_argument("--risk", type=float, default=0.5)
    ap.add_argument("--init")
    ap.add_argument("--only")
    ap.add_argument("--exclude")
    ap.add_argument("--out", required=True)
    ap.add_argument("--seed", type=int, default=7)
    a = ap.parse_args()
    tun = describe(a.task)
    init = read_params(a.init)
    fixed = dict(init)
    if a.only:
        keep = set(a.only.split(","))
        tun = [t for t in tun if t[0] in keep]
    if a.exclude:
        drop = set(a.exclude.split(","))
        tun = [t for t in tun if t[0] not in drop]
    names = [t[0] for t in tun]
    lo = np.array([t[2] for t in tun]); hi = np.array([t[3] for t in tun])
    x0 = np.array([(init.get(t[0], t[1]) - t[2]) / (t[3] - t[2]) for t in tun]).clip(0, 1)

    def to_params(x):
        p = dict(fixed)
        p.update({n: float(l + (h - l) * v) for n, l, h, v in zip(names, lo, hi, np.clip(x, 0, 1))})
        return p

    rng = np.random.default_rng(a.seed)
    es = CMA(x0, a.sigma, a.pop or None, seed=a.seed)
    print(f"robust practice: {len(names)} tunables, k={a.k}, {a.seconds}s", flush=True)
    best = (-1e18, None, None)
    t0 = time.time()
    with mp.Pool(a.workers) as pool:
        for g in range(a.gens):
            seeds = [None] + [int(s) for s in rng.integers(1, 10 ** 6, a.k - 1)]
            xs = es.ask()
            if g == 0:
                xs[0] = x0
            jobs = [(a.task, to_params(x), sd, (a.long or a.seconds) if sd is None else a.seconds) for x in xs for sd in seeds]
            res = pool.map(evaluate, jobs)
            agg, info = [], []
            for i in range(len(xs)):
                sc = [res[i * a.k + j][0] for j in range(a.k)]
                mean, mn = float(np.mean(sc)), float(np.min(sc))
                agg.append(mean - a.risk * (mean - mn))
                info.append((sc, res[i * a.k][1]))
            pen = [s - 10.0 * float(np.sum(np.maximum(0, x - 1) + np.maximum(0, -x))) for s, x in zip(agg, xs)]
            es.tell(xs, pen)
            k = int(np.argmax(agg))
            if agg[k] > best[0]:
                best = (agg[k], np.clip(xs[k], 0, 1), info[k])
                write_full(a.out, a.task, to_params(best[1]), best[0], {"scores": [round(v, 2) for v in info[k][0]], "clean": info[k][1]})
            m = info[k][1]
            print(f"gen {g + 1} best {best[0]:.2f} gen-best {agg[k]:.2f} scores {[round(v, 1) for v in info[k][0]]} sigma {es.sigma:.3f} "
                  f"({time.time() - t0:.0f}s) T={m.get('time')} d={m.get('distance')} v5={m.get('speed_last5')} z={m.get('pelvis_z')} "
                  f"cad={m.get('step_freq')} eff={m.get('effort')}", flush=True)
    print("done", best[0])


if __name__ == "__main__":
    main()
