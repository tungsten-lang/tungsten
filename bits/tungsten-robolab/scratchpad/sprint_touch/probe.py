"""probe: one or more rollouts of a task with params; prints gait metrics.
usage: probe.py TASK PARAMS [--seeds None,31] [--seconds 6] [--start flying] [--set k=v,...] [--attr k=v] [--controller p]"""
import argparse, json, os, sys, time
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "playground"))
from practice import load_task, read_params  # noqa
from bridge import Sim  # noqa
import multiprocessing as mp

KEYS = ["time", "fell", "distance", "steady_speed", "peak_speed_1s", "speed_last5", "speed", "step_freq", "step_length",
        "contact_time", "flight_time", "peak_grf", "pelvis_z", "torso_pitch", "kin_rms", "in_band", "effort", "scuffs_per_s", "score"]

def one(job):
    task_name, params, seed, seconds, start, attrs, ctl = job
    task = load_task(task_name)
    if start:
        task.start = start
    for k, v in attrs.items():
        setattr(task, k, v)
    task.seed = seed
    t0 = time.time()
    try:
        m = Sim(task, params=params, controller=ctl).run(seconds)
        m["score"] = round(float(task.score(m)), 2)
    except Exception as e:
        m = {"error": str(e)[:400]}
    m["wall"] = round(time.time() - t0, 1)
    m["seed"] = seed
    return m

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("task"); ap.add_argument("params")
    ap.add_argument("--seeds", default="None"); ap.add_argument("--seconds", type=float, default=6.0)
    ap.add_argument("--start"); ap.add_argument("--set"); ap.add_argument("--attr"); ap.add_argument("--controller")
    ap.add_argument("--workers", type=int, default=1); ap.add_argument("--all", action="store_true")
    a = ap.parse_args()
    p = read_params(a.params) if a.params != "-" else {}
    for kv in (a.set or "").split(","):
        if kv:
            k, v = kv.split("="); p[k] = float(v)
    attrs = {kv.split("=")[0]: float(kv.split("=")[1]) for kv in (a.attr or "").split(",") if kv}
    seeds = [None if s in ("None", "none") else int(s) for s in a.seeds.split(",")]
    jobs = [(a.task, p, s, a.seconds, a.start, attrs, a.controller) for s in seeds]
    if a.workers > 1:
        with mp.Pool(a.workers) as pool:
            res = pool.map(one, jobs, chunksize=1)
    else:
        res = [one(j) for j in jobs]
    for m in res:
        if a.all:
            print(json.dumps({k: v for k, v in m.items() if not isinstance(v, (list, dict))}))
        else:
            print(json.dumps({k: m.get(k) for k in ["seed"] + KEYS + ["wall", "error"] if k in m}))
