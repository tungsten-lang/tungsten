"""Champion-challenger arena for robolab trials.

Every trial (a skill on a task) has one CHAMPION: a frozen controller binary,
a params file, and its scores on the trial's fixed held-out seeds. A
CHALLENGER (any alternative approach: new params, a different skill binary,
a different body or representation) is evaluated on exactly the same seeds
and replaces the champion only if it wins a paired comparison.

    arena.py board                              # leaderboard of champions
    arena.py eval  <trial> --params p.txt [--controller bin/x] [--task t] [--note "..."]
    arena.py eval  <trial> ... --promote        # promote if it wins
    arena.py seed  <trial> --params p.txt ...   # install a first champion
    arena.py recheck [trial ...]                # re-run champions, report drift

Trials live in playground/arena/trials.json:

    {"run_v2": {"task": "run_v2", "metric": "steady_speed", "higher": true,
                "seeds": [101, 102, ...], "seconds": 30, "env": {},
                "guard": {"fell": false}, "python": "robolab"}}

`metric` is a key of the task's metrics dict, or "a+b" / "a-b" style
expressions of keys; `guard` entries must hold for a rollout to count (a
failed guard scores the rollout as the metric's worst value). MyoSuite trials
set "python": "myo" (they must run under .venv-myo). Per-seed rollouts use
`task.seed = seed` (robolab tasks perturb their start from it; MyoSuite tasks
pick the episode from it).

Decision rule: paired per-seed differences (challenger - champion). The
challenger wins if the mean difference is positive (for higher-is-better)
and a sign-flip permutation test gives p < 0.05, or, for 0/1 metrics, if the
success-rate CI of the difference excludes zero. Ties keep the champion.
"""

import argparse
import contextlib
import fcntl
import importlib
import json
import math
import os
import shutil
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DIR = os.path.join(HERE, "arena")
TRIALS = os.path.join(DIR, "trials.json")
CHAMPS = os.path.join(DIR, "champions.json")
HISTORY = os.path.join(DIR, "history.jsonl")


def load_json(path, default):
    if os.path.exists(path):
        with open(path) as f:
            return json.load(f)
    return default


def save_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + f".{os.getpid()}"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=1, sort_keys=True)
    os.replace(tmp, path)


@contextlib.contextmanager
def locked():
    """Serialise read-modify-write of champions.json across concurrent arena runs."""
    os.makedirs(DIR, exist_ok=True)
    with open(os.path.join(DIR, ".lock"), "w") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(f, fcntl.LOCK_UN)


def install(trial_name, entry, beaten=None):
    """Write one champion, re-reading the file under the lock so a concurrent
    promotion of another trial is not overwritten. `beaten` is the champion the
    challenger was compared against; if another run replaced it meanwhile, the
    comparison is stale and nothing is installed."""
    with locked():
        champs = load_json(CHAMPS, {})
        current = champs.get(trial_name)
        if beaten is not None and (current or {}).get("frozen_controller") != beaten.get("frozen_controller"):
            return False
        champs[trial_name] = entry
        save_json(CHAMPS, champs)
        return True


def read_params(path):
    out = {}
    if path:
        for line in open(path):
            t = line.split()
            if len(t) >= 2 and not line.startswith("#"):
                out[t[0]] = float(t[1])
    return out


def metric_value(expr, metrics):
    total = 0.0
    sign = 1.0
    token = ""
    for ch in expr + "+":
        if ch in "+-":
            if token:
                v = metrics.get(token.strip())
                if v is None:
                    return None
                total += sign * float(v)
            sign = 1.0 if ch == "+" else -1.0
            token = ""
        else:
            token += ch
    return total


def rollout(job):
    trial, params, controller, task_name, seed = job
    for k, v in trial.get("env", {}).items():
        os.environ[k] = str(v)
    sys.path.insert(0, HERE)
    task = importlib.import_module(f"tasks.{task_name}").TASK()
    task.seed = seed
    if trial.get("python") == "myo":
        from myo_bridge import MyoSim
        sim = MyoSim(task, params=params, controller=controller, seed=seed)
    else:
        from bridge import Sim
        sim = Sim(task, params=params, controller=controller)
    try:
        m = sim.run(trial.get("seconds"))
    except Exception as e:  # a crashing rollout scores worst
        return {"error": str(e)[:200]}
    return {k: (float(v) if isinstance(v, (int, float)) and not isinstance(v, bool) else v)
            for k, v in m.items() if isinstance(v, (int, float, bool, str)) or v is None}


def score_rollouts(trial, rows):
    worst = -1e9 if trial.get("higher", True) else 1e9
    out = []
    for m in rows:
        if "error" in m:
            out.append(worst)
            continue
        ok = all(m.get(k) == v for k, v in trial.get("guard", {}).items())
        v = metric_value(trial["metric"], m)
        out.append(worst if (not ok or v is None) else v)
    return out


def evaluate(trial, params, controller, task_name, workers):
    import multiprocessing as mp
    jobs = [(trial, params, controller, task_name, s) for s in trial["seeds"]]
    with mp.get_context("spawn").Pool(workers) as pool:
        rows = pool.map(rollout, jobs)
    return rows, score_rollouts(trial, rows)


def compare(trial, champ_scores, chal_scores, rng_seed=0):
    import random
    higher = trial.get("higher", True)
    diffs = [(c - h) if higher else (h - c) for c, h in zip(chal_scores, champ_scores)]
    n = len(diffs)
    mean = sum(diffs) / n
    rng = random.Random(rng_seed)
    extreme = 0
    reps = 4000
    for _ in range(reps):
        s = sum(d if rng.random() < 0.5 else -d for d in diffs) / n
        if s >= mean - 1e-12:
            extreme += 1
    p = extreme / reps
    if n < 5:  # deterministic trials: no sample to test, require a strict gain
        return {"mean_diff": mean, "p": None, "n": n, "wins": mean > 1e-9}
    wins = mean > 0 and p < 0.05
    return {"mean_diff": mean, "p": p, "n": n, "wins": wins}


def summary(scores):
    n = len(scores)
    mean = sum(scores) / n
    var = sum((s - mean) ** 2 for s in scores) / max(n - 1, 1)
    return {"mean": mean, "ci95": 1.96 * math.sqrt(var / n), "n": n}


def freeze(trial_name, params_path, controller):
    dest = os.path.join(ROOT, "bin", "champions")
    os.makedirs(dest, exist_ok=True)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    binpath = os.path.join(dest, f"{trial_name}-{stamp}")
    shutil.copy2(controller, binpath)
    pdest = os.path.join(DIR, "params", f"{trial_name}-{stamp}.txt")
    os.makedirs(os.path.dirname(pdest), exist_ok=True)
    if params_path:
        shutil.copy2(params_path, pdest)
    else:
        open(pdest, "w").close()
    return os.path.relpath(binpath, ROOT), os.path.relpath(pdest, ROOT)


def default_controller(task_name):
    sys.path.insert(0, HERE)
    task = importlib.import_module(f"tasks.{task_name}").TASK()
    return task.controller or os.path.join(ROOT, "bin", f"robolab_{task.name}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["board", "eval", "seed", "recheck"])
    ap.add_argument("trial", nargs="*")
    ap.add_argument("--params")
    ap.add_argument("--controller")
    ap.add_argument("--task")
    ap.add_argument("--note", default="")
    ap.add_argument("--workers", type=int, default=3)
    ap.add_argument("--promote", action="store_true")
    ap.add_argument("--force", action="store_true", help="seed over an existing champion")
    args = ap.parse_args()
    trials = load_json(TRIALS, {})
    champs = load_json(CHAMPS, {})

    if args.cmd == "board":
        # Failed guards and crashes score +-1e9, so the mean is shown over the
        # rollouts that passed, beside the pass count.
        print(f"{'trial':<20}{'metric':<18}{'champion':>10}  {'±':<7}{'pass':>7}  approach")
        for name in sorted(trials):
            t = trials[name]
            c = champs.get(name)
            if not c:
                print(f"{name:<20}{t['metric']:<18}{'(none)':>10}")
                continue
            ok = [x for x in c.get("scores", []) if abs(x) < 1e8]
            n = len(c.get("scores", [])) or c["summary"]["n"]
            s = summary(ok) if ok else {"mean": float("nan"), "ci95": 0.0}
            note = c["note"] if len(c["note"]) <= 60 else c["note"][:57] + "..."
            print(f"{name:<20}{t['metric']:<18}{s['mean']:>10.4f}  {s['ci95']:<7.3f}{len(ok):>3}/{n:<3}  {note}")
        return

    if args.cmd == "recheck":
        # Champions freeze their binary and params, not the task .py files, so a
        # later edit to a task, body or bridge can change what a champion scores.
        # Re-run each champion on its own seeds and report any per-seed drift.
        py = "myo" if "venv-myo" in sys.executable else "robolab"
        for name in (args.trial or sorted(champs)):
            c, t = champs.get(name), trials.get(name)
            if not c or not t or (t.get("python", "robolab") != py):
                continue
            ctl = os.path.join(ROOT, c["frozen_controller"])
            rows, scores = evaluate(t, read_params(os.path.join(ROOT, c["frozen_params"])), ctl, c["task"], args.workers)
            drift = [round(a - b, 4) for a, b in zip(scores, c["scores"]) if abs(a - b) > 1e-6]
            state = "OK" if not drift else f"DRIFT on {len(drift)}/{len(scores)} seeds {drift[:6]}"
            print(f"{name}: stored {c['summary']['mean']:.4f}, now {summary(scores)['mean']:.4f}  {state}")
        return

    args.trial = args.trial[0]
    trial = trials[args.trial]
    if args.cmd == "seed" and args.trial in champs and not args.force:
        print(f"{args.trial} already has a champion ({champs[args.trial]['note']}); "
              "challenge it with `eval`, or pass --force to replace it")
        return
    task_name = args.task or trial["task"]
    controller = os.path.abspath(args.controller) if args.controller else default_controller(task_name)
    params = read_params(args.params)
    t0 = time.time()
    rows, scores = evaluate(trial, params, controller, task_name, args.workers)
    summ = summary(scores)
    print(f"{args.trial}: {trial['metric']} = {summ['mean']:.4f} ± {summ['ci95']:.4f} over {summ['n']} seeds ({time.time() - t0:.0f}s)")
    entry = {"trial": args.trial, "task": task_name, "params": args.params, "controller": controller,
             "note": args.note, "summary": summ, "scores": scores, "time": time.strftime("%Y-%m-%d %H:%M:%S")}
    # opt-in secondary metrics (a trial's "report" keys, e.g. the official
    # score beside a stricter metric, or effort): means over the rollouts
    # that ran, recorded with the entry; they never decide anything
    if trial.get("report"):
        ran = [m for m in rows if "error" not in m]
        rep = {}
        for k in trial["report"]:
            vals = [float(m[k]) for m in ran if isinstance(m.get(k), (int, float))]
            if vals:
                rep[k] = round(sum(vals) / len(vals), 5)
        entry["report"] = rep
        print("report: " + ", ".join(f"{k} {v:.4f}" for k, v in rep.items()))

    if args.cmd == "seed" or args.trial not in champs:
        binp, pp = freeze(args.trial, args.params, controller)
        entry.update({"frozen_controller": binp, "frozen_params": pp, "result": "seeded"})
        install(args.trial, entry)
        print("installed as champion")
    else:
        champ = champs[args.trial]
        cmp = compare(trial, champ["scores"], scores)
        entry["vs_champion"] = cmp
        verdict = "WINS" if cmp["wins"] else "does not beat"
        ptxt = "deterministic" if cmp["p"] is None else f"p = {cmp['p']:.3f}"
        print(f"challenger {verdict} champion ({champ['summary']['mean']:.4f}, {champ['note']}): "
              f"mean paired diff {cmp['mean_diff']:+.4f}, {ptxt}")
        entry["result"] = "win" if cmp["wins"] else "lose"
        if cmp["wins"] and args.promote:
            binp, pp = freeze(args.trial, args.params, controller)
            entry.update({"frozen_controller": binp, "frozen_params": pp, "result": "promoted"})
            if install(args.trial, entry, beaten=champ):
                print("promoted to champion")
            else:
                entry["result"] = "stale"
                print("NOT promoted: the champion changed during this evaluation; re-run against the new one")
    with locked(), open(HISTORY, "a") as f:
        f.write(json.dumps({k: v for k, v in entry.items() if k != "scores"}) + "\n")


if __name__ == "__main__":
    main()
