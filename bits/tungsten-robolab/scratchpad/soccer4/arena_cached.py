"""The arena CLI with per-seed rollout caching (state in the repo, survives a reboot).

    .venv-myo/bin/python scratchpad/soccer4/arena_cached.py eval soccer_single_leg_310_40 --params P --controller C --note ... [--promote]

Identical to playground/arena.py (same rollout function, same trial definition, same paired test): the only change is
that every finished rollout is stored under scratchpad/soccer4/evalcache/<hash of controller bytes, params, env, seed>.json
and reused if the same rollout is asked for again (so a killed evaluation resumes, and a re-run is free), and that the
per-seed result rows are written to scratchpad/soccer4/evals/<trial>-<controller>-<time>.json for analysis.
"""
import hashlib
import json
import multiprocessing as mp
import os
import sys
import time

HERE = "/Users/erik/tungsten/bits/tungsten-robolab"
sys.path.insert(0, os.path.join(HERE, "playground"))
import arena  # noqa: E402

CACHE = os.path.join(HERE, "scratchpad", "soccer4", "evalcache")
EVALS = os.path.join(HERE, "scratchpad", "soccer4", "evals")


def rollout_key(trial, params, controller, task_name, seed):
    h = hashlib.sha1()
    with open(controller, "rb") as f:
        h.update(f.read())
    h.update(json.dumps(params, sort_keys=True).encode())
    h.update(json.dumps(trial.get("env", {}), sort_keys=True).encode())
    h.update(f"{task_name}:{seed}:{trial.get('seconds')}:{trial.get('python')}".encode())
    return h.hexdigest()[:24]


def cached_rollout(job):
    trial, params, controller, task_name, seed = job
    path = os.path.join(CACHE, rollout_key(trial, params, controller, task_name, seed) + ".json")
    if os.path.exists(path):
        with open(path) as f:
            return json.load(f)
    row = arena.rollout(job)
    if "error" not in row:
        os.makedirs(CACHE, exist_ok=True)
        tmp = path + f".{os.getpid()}"
        with open(tmp, "w") as f:
            json.dump(row, f)
        os.replace(tmp, path)
    return row


def evaluate(trial, params, controller, task_name, workers):
    jobs = [(trial, params, controller, task_name, s) for s in trial["seeds"]]
    with mp.get_context("spawn").Pool(workers) as pool:
        rows = pool.map(cached_rollout, jobs)
    os.makedirs(EVALS, exist_ok=True)
    tag = os.path.basename(controller)
    out = os.path.join(EVALS, f"{trial.get('metric')}-{tag}-{time.strftime('%Y%m%d-%H%M%S')}.json")
    with open(out, "w") as f:
        json.dump({"seeds": trial["seeds"], "rows": rows, "controller": controller}, f)
    print("per-seed rows:", out, flush=True)
    return rows, arena.score_rollouts(trial, rows)


if __name__ == "__main__":
    arena.evaluate = evaluate
    arena.main()
