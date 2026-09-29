"""Search and evaluation driver for the MyoChallenge manipulation skills
(myo_relocate, myo_baoding, myo_die, myo_bimanual and their _eval variants).

Not a task module itself. Two things practice.py / robust_practice.py do not:

* Episodes reuse one MyoSuite environment per worker process (ReuseSim):
  building the env and its muscle geometry costs as much as a whole
  150-step episode. Each episode reseeds the env (`u.seed(s)` then
  `reset(seed=s)`, exactly what MyoSim does), so an episode here is the
  same episode myo_bridge.py runs for that seed; `check` verifies it.
* Candidates are scored over K seeds with common random numbers (every
  candidate of a generation sees the same seeds), aggregated as
  mean - risk * (mean - min), and the evaluation mode reports the official
  success rate with a Wilson 95% interval.

    python playground/tasks/myo_manip.py search myo_relocate --k 8 --gens 30 --out params/myo_relocate.txt
    python playground/tasks/myo_manip.py opt myo_baoding_spin --method bo --budget 800 --k 4 --out params/x.txt
    python playground/tasks/myo_manip.py eval myo_relocate --params params/myo_relocate.txt --n 100 --json out/x.json
    python playground/tasks/myo_manip.py check myo_relocate --params params/myo_relocate.txt
    python playground/tasks/myo_manip.py final myo_relocate --name myo_relocate --params params/myo_relocate.txt --n 200 --video-seed 10003
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
PLAY = os.path.dirname(HERE)
ROOT = os.path.dirname(PLAY)
sys.path.insert(0, PLAY)

from myo_bridge import MyoSim, load_task, muscle_geometry  # noqa: E402
from practice import CMA, describe, read_params  # noqa: E402


class ReuseSim(MyoSim):
    """A MyoSim whose environment survives from one episode to the next."""

    def new_episode(self, seed, params):
        self.seed = seed
        self.params = params or {}
        self.u.seed(seed)
        self.obs, _ = self.env.reset(seed=seed)
        ref = self.d.qpos.copy()
        key = np.round(ref[[j[5] for j in self.joints]], 12).tobytes()
        if key != getattr(self, "_geom_key", None):
            self.joints, self.table, self.lref = muscle_geometry(
                self.m, self.muscle_ids, ref, coupled=getattr(self.task, "coupled_geometry", False))
            self._geom_key = np.round(ref[[j[5] for j in self.joints]], 12).tobytes()
        self.motor_cmd = {k: 0.0 for k in self.motor_cmd}
        self.label = ""
        self.targets = np.zeros(self.n)
        self.log = []
        self.infos = []
        self.done = False
        self._ep = {}
        return self


_SIMS = {}


def get_sim(task_name, seed, params):
    sim = _SIMS.get(task_name)
    if sim is None:
        task = load_task(task_name)
        sim = ReuseSim(task, params=params, seed=seed)
        sim._geom_key = np.round(sim.d.qpos[[j[5] for j in sim.joints]], 12).tobytes()
        sim._ep = {}
        _SIMS[task_name] = sim
        return sim
    return sim.new_episode(seed, params)


def run_episode(job):
    task_name, params, seed = job
    try:
        sim = get_sim(task_name, seed, params)
        m = sim.run()
        m["seed"] = seed
        return sim.task.score(m), m
    except Exception as e:  # a crashing candidate scores worst
        _SIMS.pop(task_name, None)
        return -1e9, {"error": str(e)[:300], "seed": seed}


def wilson(k, n, z=1.96):
    if n == 0:
        return 0.0, 0.0
    p = k / n
    den = 1 + z * z / n
    mid = (p + z * z / (2 * n)) / den
    half = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / den
    return max(0.0, mid - half), min(1.0, mid + half)


def mean_ci(xs, z=1.96):
    xs = np.asarray(xs, float)
    if len(xs) < 2:
        return float(xs.mean()) if len(xs) else 0.0, 0.0
    return float(xs.mean()), float(z * xs.std(ddof=1) / math.sqrt(len(xs)))


def summarize(results, primary="success"):
    ok = [r for r in results if "error" not in r]
    out = {"episodes": len(results), "errors": len(results) - len(ok)}
    if not ok:
        return out
    keys = [k for k in ok[0] if isinstance(ok[0][k], (int, float)) and not isinstance(ok[0][k], bool)]
    for k in keys:
        out[k] = round(float(np.mean([r[k] for r in ok])), 5)
    if primary in ok[0]:
        vals = [float(r[primary]) for r in ok]
        if set(vals) <= {0.0, 1.0}:
            k = int(sum(vals))
            lo, hi = wilson(k, len(vals))
            out[primary + "_ci95"] = [round(lo, 4), round(hi, 4)]
        else:
            mu, half = mean_ci(vals)
            out[primary + "_ci95"] = [round(mu - half, 4), round(mu + half, 4)]
    return out


def write_params(path, task, params, score, info):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w") as f:
        f.write(f"# robolab myo_manip search result for {task}: score {score:.4f}\n# {info}\n")
        for k in sorted(params):
            if not k.startswith("__"):
                f.write(f"{k} {float(params[k])!r}\n")


def cmd_search(a):
    from search import describe as describe_with
    init = read_params(a.init)
    tun = describe_with(a.task, fixed=init)
    fixed = dict(init)
    if a.only:
        keep = set(a.only.split(","))
        tun = [t for t in tun if t[0] in keep]
    if a.exclude:
        drop = set(a.exclude.split(","))
        tun = [t for t in tun if t[0] not in drop]
    tun = [t for t in tun if t[3] > t[2]]
    names = [t[0] for t in tun]
    lo = np.array([t[2] for t in tun])
    hi = np.array([t[3] for t in tun])
    x0 = np.array([(init.get(t[0], t[1]) - t[2]) / (t[3] - t[2]) for t in tun]).clip(0, 1)

    def to_params(x):
        p = dict(fixed)
        p.update({n: float(l + (h - l) * v) for n, l, h, v in zip(names, lo, hi, np.clip(x, 0, 1))})
        return p

    rng = np.random.default_rng(a.seed)
    es = CMA(x0, a.sigma, a.pop or None, seed=a.seed)
    fixed_seeds = [a.seed_base + i for i in range(a.k)]
    print(f"search {a.task}: {len(names)} tunables {names}, pop {es.lam}, k={a.k} "
          f"({'fresh' if a.fresh else 'fixed'} seeds), workers {a.workers}", flush=True)
    best = (-1e18, None, None)
    t0 = time.time()
    with mp.Pool(a.workers) as pool:
        for g in range(a.gens):
            seeds = [int(s) for s in rng.integers(10_000, 10 ** 6, a.k)] if a.fresh else fixed_seeds
            xs = es.ask()
            if g == 0:
                xs[0] = x0
            jobs = [(a.task, to_params(x), sd) for x in xs for sd in seeds]
            res = pool.map(run_episode, jobs, chunksize=1)
            agg, info = [], []
            for i in range(len(xs)):
                sc = [res[i * a.k + j][0] for j in range(a.k)]
                ms = [res[i * a.k + j][1] for j in range(a.k)]
                mean, mn = float(np.mean(sc)), float(np.min(sc))
                agg.append(mean - a.risk * (mean - mn))
                info.append(summarize(ms))
            pen = [s - 10.0 * float(np.sum(np.maximum(0, x - 1) + np.maximum(0, -x))) for s, x in zip(agg, xs)]
            es.tell(xs, pen)
            k = int(np.argmax(agg))
            if agg[k] > best[0]:
                best = (agg[k], np.clip(xs[k], 0, 1), info[k])
                write_params(a.out, a.task, to_params(best[1]), best[0], {"gen": g + 1, "summary": info[k]})
            s = info[k]
            print(f"gen {g + 1} best {best[0]:.4f} gen-best {agg[k]:.4f} gen-mean {np.mean(agg):.4f} sigma {es.sigma:.3f} "
                  f"({time.time() - t0:.0f}s) succ {s.get('success', s.get('score'))} eff {s.get('act_sq')} "
                  f"{ {kk: s.get(kk) for kk in a.show.split(',') if kk in s} }", flush=True)
    print("done", best[0], best[2])


def cmd_opt(a):
    """Any optimizer of playground/search.py (bo, oneplusone, sep_cma, cma, ...)
    over the skill's tunables, with this module's env-reusing rollouts.
    Each candidate is scored on --k seeds: a fixed set (--seed-base..) for the
    elitist / model-based methods, or fresh common seeds per ask (--fresh),
    aggregated as mean - risk * (mean - min). Stops after --budget rollouts."""
    from search import make_optimizer, describe as describe_with
    init = read_params(a.init)
    # declared defaults may depend on other params (a gait state defaults to
    # the cup), so describe the skill with the init params applied
    tun = describe_with(a.task, fixed=init)
    fixed = dict(init)
    for kv in (a.fixed or "").split(","):
        if kv:
            k, v = kv.split("=")
            fixed[k] = float(v)
    if a.only:
        keep = a.only.split(",")
        tun = [t for t in tun if any(t[0] == k or (k.endswith("*") and t[0].startswith(k[:-1])) for k in keep)]
    if a.exclude:
        drop = set(a.exclude.split(","))
        tun = [t for t in tun if t[0] not in drop]
    tun = [t for t in tun if t[3] > t[2]]
    names = [t[0] for t in tun]
    lo = np.array([t[2] for t in tun])
    hi = np.array([t[3] for t in tun])
    x0 = np.array([(init.get(t[0], t[1]) - t[2]) / (t[3] - t[2]) for t in tun]).clip(0, 1)

    def to_params(x):
        p = dict(fixed)
        p.update({n: float(l + (h - l) * v) for n, l, h, v in zip(names, lo, hi, np.clip(x, 0, 1))})
        return p

    rng = np.random.default_rng(a.seed)
    fixed_seeds = [a.seed_base + i for i in range(a.k)]
    used = 0
    best = (-1e18, None, None)
    t0 = time.time()
    log = open(a.out + ".jsonl", "w") if a.out else None
    print(f"opt {a.task} {a.method}: {len(names)} tunables, k={a.k} ({'fresh' if a.fresh else 'fixed'} seeds), "
          f"budget {a.budget}, workers {a.workers}", flush=True)
    with mp.Pool(a.workers) as pool:
        # x0 first (every method's reference)
        def score(X):
            seeds = [int(s) for s in rng.integers(10_000, 10 ** 6, a.k)] if a.fresh else fixed_seeds
            jobs = [(a.task, to_params(x), sd) for x in X for sd in seeds]
            res = pool.map(run_episode, jobs, chunksize=1)
            agg, info = [], []
            for i in range(len(X)):
                sc = [res[i * a.k + j][0] for j in range(a.k)]
                mean, mn = float(np.mean(sc)), float(np.min(sc))
                agg.append(mean - a.risk * (mean - mn))
                info.append(summarize([res[i * a.k + j][1] for j in range(a.k)]))
            return agg, info
        f0, i0 = score(np.array([x0]))
        used += a.k
        best = (f0[0], x0.copy(), i0[0])
        opt = make_optimizer(a.method, x0, sigma0=a.sigma, seed=a.seed, f0=f0[0])
        gen = 0
        while used < a.budget:
            X = np.atleast_2d(opt.ask())
            f, info = score(np.clip(X, 0, 1))
            used += len(X) * a.k
            opt.tell(X, np.asarray(f), info)
            gen += 1
            k = int(np.argmax(f))
            if f[k] > best[0]:
                best = (f[k], np.clip(X[k], 0, 1), info[k])
                write_params(a.out, a.task, to_params(best[1]), best[0], {"rollouts": used, "summary": info[k]})
            if log:
                log.write(json.dumps({"rollouts": used, "best": best[0], "f": [float(v) for v in f]}) + "\n")
                log.flush()
            if gen % max(1, a.every) == 0:
                s = best[2]
                print(f"{used} rollouts best {best[0]:.4f} ask-best {max(f):.4f} ({time.time() - t0:.0f}s) "
                      f"{ {kk: s.get(kk) for kk in a.show.split(',') if kk in s} } {opt.info()}", flush=True)
    write_params(a.out, a.task, to_params(best[1]), best[0], {"rollouts": used, "summary": best[2]})
    # with fresh seeds the best-so-far is biased toward lucky draws; the
    # distribution mean (CMA-type methods) is the better estimate
    mean = getattr(opt, "mean", None)
    if mean is not None and a.out:
        write_params(a.out.replace(".txt", "_mean.txt"), a.task, to_params(np.clip(mean, 0, 1)), float("nan"),
                     {"rollouts": used, "note": "optimizer mean"})
    print("done", best[0], best[2], flush=True)


def cmd_eval(a):
    params = read_params(a.params) if a.params else {}
    for kv in a.set or []:
        k, v = kv.split("=")
        params[k] = float(v)
    seeds = list(range(a.seed0, a.seed0 + a.n))
    t0 = time.time()
    with mp.Pool(a.workers) as pool:
        res = pool.map(run_episode, [(a.task, params, s) for s in seeds], chunksize=1)
    ms = [r[1] for r in res]
    summ = summarize(ms, a.primary)
    summ["wall_s"] = round(time.time() - t0, 1)
    summ["task"] = a.task
    summ["params"] = a.params
    summ["seeds"] = [seeds[0], seeds[-1]]
    print(json.dumps(summ))
    if a.json:
        os.makedirs(os.path.dirname(a.json) or ".", exist_ok=True)
        json.dump({"summary": summ, "episodes": ms}, open(a.json, "w"), indent=1, default=float)


LEADERBOARD = {
    "myo_relocate": ("MyoChallenge 2023 Relocate phase 2, winner Lattice", 0.343),
    "myo_relocate_eval": ("MyoChallenge 2023 Relocate phase 2, winner Lattice", 0.343),
    "myo_baoding": ("MyoChallenge 2022 Baoding phase 2, winner stiff_fingers", 0.55),
    "myo_die": ("MyoChallenge 2022 Die reorientation phase 2, co-winners IARAI-JKU / pkumarl", 0.13),
    "myo_bimanual": ("MyoChallenge 2024 Bimanual handover, winner Muscle Heads", 0.26),
}
PRIMARY = {"myo_baoding": "score"}


def cmd_final(a):
    """Official evaluation on N seeds + showcase video/gif/sheet via myo_bridge."""
    import subprocess
    params = read_params(a.params) if a.params else {}
    seeds = list(range(a.seed0, a.seed0 + a.n))
    primary = PRIMARY.get(a.task, "success")
    t0 = time.time()
    with mp.Pool(a.workers) as pool:
        res = pool.map(run_episode, [(a.task, params, s) for s in seeds], chunksize=1)
    ms = [r[1] for r in res]
    summ = summarize(ms, primary)
    ok = [m for m in ms if "error" not in m]
    summ["effort_act_sq_ci95"] = list(np.round(mean_ci([m["act_sq"] for m in ok])[0] + np.array([-1, 1]) * mean_ci([m["act_sq"] for m in ok])[1], 5))
    if "task" in (ok[0] if ok else {}):
        by = {}
        for m in ok:
            by.setdefault(m["task"], []).append(m[primary])
        summ["by_task"] = {k: {"n": len(v), "mean": round(float(np.mean(v)), 4)} for k, v in by.items()}
    task = load_task(a.task)
    board = LEADERBOARD.get(a.task)
    out = {
        "task": a.task, "env_id": task.env_id, "params": a.params, "episodes": len(seeds),
        "seeds": [seeds[0], seeds[-1]], "primary": primary,
        "official": {"value": summ.get(primary), "ci95": summ.get(primary + "_ci95")},
        "leaderboard": {"who": board[0], "score": board[1]} if board else None,
        "effort": {"mean_sq_activation": summ.get("act_sq"), "mean_sq_activation_ci95": summ["effort_act_sq_ci95"],
                   "myosuite_act_reg": summ.get("effort_official")},
        "summary": summ, "notes": a.notes or "", "wall_s": round(time.time() - t0, 1),
        "episodes_detail": ms,
    }
    base = os.path.join(ROOT, "out", a.name)
    json.dump(out, open(base + "_metrics.json", "w"), indent=1, default=float)
    print(json.dumps({k: out[k] for k in ("task", "official", "leaderboard", "effort")}, default=float))
    if a.video_seed is not None:
        cmd = [sys.executable, os.path.join(PLAY, "myo_bridge.py"), a.task, "--seed", str(a.video_seed),
               "--video", base + ".mp4", "--gif", base + ".gif", "--sheet", base + "_sheet.png",
               "--json", base + "_showcase.json"]
        if a.params:
            cmd += ["--params", a.params]
        subprocess.run(cmd, check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        print("showcase", a.video_seed, [f for f in os.listdir(os.path.join(ROOT, "out")) if f.startswith(a.name)])


def cmd_check(a):
    """The reused-env episode must equal a fresh MyoSim episode for a seed."""
    params = read_params(a.params) if a.params else {}
    task = load_task(a.task)
    for seed in (a.seed0, a.seed0 + 1, a.seed0 + 2):
        fresh = MyoSim(task, params=params, seed=seed).run()
        _, reused = run_episode((a.task, params, seed))
        same = all(fresh.get(k) == reused.get(k) for k in fresh if k not in ("wall_s",))
        print(seed, "identical" if same else "DIFFERENT", {k: (fresh[k], reused.get(k)) for k in fresh
                                                           if fresh.get(k) != reused.get(k)})


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("search")
    s.add_argument("task")
    s.add_argument("--gens", type=int, default=30)
    s.add_argument("--pop", type=int, default=0)
    s.add_argument("--workers", type=int, default=2)
    s.add_argument("--sigma", type=float, default=0.12)
    s.add_argument("--k", type=int, default=8)
    s.add_argument("--risk", type=float, default=0.0)
    s.add_argument("--fresh", action="store_true", help="fresh random seeds each generation")
    s.add_argument("--seed-base", type=int, default=1000)
    s.add_argument("--init")
    s.add_argument("--only")
    s.add_argument("--exclude")
    s.add_argument("--out", required=True)
    s.add_argument("--seed", type=int, default=3)
    s.add_argument("--show", default="min_dist,max_obj_z,solved_steps")
    o = sub.add_parser("opt")
    o.add_argument("task")
    o.add_argument("--method", default="sep_cma")
    o.add_argument("--budget", type=int, default=800)
    o.add_argument("--workers", type=int, default=3)
    o.add_argument("--sigma", type=float, default=0.15)
    o.add_argument("--k", type=int, default=4)
    o.add_argument("--risk", type=float, default=0.0)
    o.add_argument("--fresh", action="store_true")
    o.add_argument("--seed-base", type=int, default=1000)
    o.add_argument("--seed", type=int, default=1)
    o.add_argument("--init")
    o.add_argument("--fixed")
    o.add_argument("--only")
    o.add_argument("--exclude")
    o.add_argument("--out", required=True)
    o.add_argument("--every", type=int, default=5)
    o.add_argument("--show", default="success,success_lift,score,held_frac,turn")
    e = sub.add_parser("eval")
    e.add_argument("task")
    e.add_argument("--params")
    e.add_argument("--n", type=int, default=100)
    e.add_argument("--seed0", type=int, default=0)
    e.add_argument("--workers", type=int, default=2)
    e.add_argument("--primary", default="success")
    e.add_argument("--json")
    e.add_argument("--set", nargs="*")
    c = sub.add_parser("check")
    c.add_argument("task")
    c.add_argument("--params")
    c.add_argument("--seed0", type=int, default=0)
    fz = sub.add_parser("final")
    fz.add_argument("task")
    fz.add_argument("--name", required=True, help="output basename under out/")
    fz.add_argument("--params")
    fz.add_argument("--n", type=int, default=100)
    fz.add_argument("--seed0", type=int, default=10000)
    fz.add_argument("--workers", type=int, default=2)
    fz.add_argument("--video-seed", type=int)
    fz.add_argument("--notes")
    a = ap.parse_args()
    {"search": cmd_search, "opt": cmd_opt, "eval": cmd_eval, "check": cmd_check, "final": cmd_final}[a.cmd](a)


if __name__ == "__main__":
    main()
