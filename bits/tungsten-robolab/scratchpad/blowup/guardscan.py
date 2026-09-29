"""Run jobs (seed, params, controller, seconds) with the nanguard task (tasks/myo_soccer_ng.py) and print the guard counters.

usage: guardscan.py --jobs jobs.json [--workers 2] [--mode 1|0] [--json out.json]
jobs.json: [{"tag": "89122-shc", "seed": 89122, "params": "params/x.txt", "controller": "bin/challengers/y", "seconds": 46}, ...]
Mode 1 (default) nudges and continues; mode 0 counts only (the official behaviour). Per job: stand_time, bal1_raw, fallen, t_fall and nan_*."""
import argparse, json, os, sys, time
import multiprocessing as mp

HERE = "/Users/erik/tungsten/bits/tungsten-robolab"
sys.path.insert(0, os.path.join(HERE, "playground"))
sys.path.insert(0, os.path.join(HERE, "scratchpad", "soccer4"))


def run(job):
    os.environ["MYO_SOCCER_ENV"] = "myoChallengeSoccerP2-v0"
    os.environ["MYO_SOCCER_MAX_TIME"] = "310"
    os.environ["MYO_SOCCER_NANGUARD"] = job["mode"]
    from search4 import read_params
    from myo_bridge import MyoSim
    from tasks.myo_soccer_ng import NanGuardSoccerTask
    t0 = time.time()
    try:
        sim = MyoSim(NanGuardSoccerTask(), params=read_params(os.path.join(HERE, job["params"])),
                     controller=os.path.join(HERE, job["controller"]), seed=job["seed"])
        res = sim.run(job["seconds"])
    except Exception as e:
        return {"tag": job["tag"], "error": str(e)[:200]}
    keep = {k: res.get(k) for k in ("time", "stand_time", "bal1_raw", "bal1_300", "fallen", "t_fall", "nan_events", "nan_nudged", "nan_other", "nan_first_t", "nan_tendons", "hold20")}
    keep.update(tag=job["tag"], seed=job["seed"], wall=round(time.time() - t0, 1), seconds=job["seconds"])
    return keep


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--jobs", required=True); ap.add_argument("--workers", type=int, default=2)
    ap.add_argument("--mode", default="1"); ap.add_argument("--json")
    a = ap.parse_args()
    jobs = json.load(open(a.jobs))
    for j in jobs:
        j["mode"] = a.mode
    out = []
    with mp.get_context("spawn").Pool(a.workers) as pool:
        for r in pool.imap_unordered(run, jobs):
            print(json.dumps(r), flush=True)
            out.append(r)
    if a.json:
        json.dump(out, open(a.json, "w"), indent=1)
