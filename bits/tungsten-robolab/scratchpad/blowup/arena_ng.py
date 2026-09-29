"""playground/arena.py with per-seed rollout caching (resumable, state in the repo) for the nanguard trials.

    .venv-myo/bin/python scratchpad/blowup/arena_ng.py eval soccer_hold20_120_ng --params P --controller C --note ... [--promote] [--workers 2]
    .venv-myo/bin/python scratchpad/blowup/arena_ng.py seed soccer_hold20_120_ng --params P --controller C --note ...

Same rollout function, trial definition and paired test as arena.py; only (1) every finished rollout is stored under scratchpad/blowup/evalcache/
keyed by the sha1 of the controller bytes, params, env, task name, seed, seconds AND the bytes of the task/bridge python files (a stale
cache can never survive a task edit), and reused when asked again (a killed evaluation resumes), and (2) the per-seed rows go to
scratchpad/blowup/evals/<trial>-<controller>-<time>.json. Copied from scratchpad/soccer4/arena_cached.py (state paths and cache key changed)."""
import hashlib
import json
import multiprocessing as mp
import os
import sys
import time

HERE = "/Users/erik/tungsten/bits/tungsten-robolab"
sys.path.insert(0, os.path.join(HERE, "playground"))
import arena  # noqa: E402

CACHE = os.path.join(HERE, "scratchpad", "blowup", "evalcache")
EVALS = os.path.join(HERE, "scratchpad", "blowup", "evals")
CODE = [os.path.join(HERE, "playground", "tasks", f) for f in ("myo_soccer.py", "myo_soccer_ng.py")] + [os.path.join(HERE, "playground", "myo_bridge.py")]


def rollout_key(trial, params, controller, task_name, seed):
    h = hashlib.sha1()
    with open(controller, "rb") as f:
        h.update(f.read())
    for p in CODE:
        with open(p, "rb") as f:
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
        rows = pool.map(cached_rollout, jobs, chunksize=1)
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
