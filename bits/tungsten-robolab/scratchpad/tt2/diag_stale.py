"""Post-verdict diagnostic (agent T2): the same beyond-arm episodes with the bridge telling the controller the OFFICIAL peak forces (a stale MFORCE and a
stale normalised-force reflex input) instead of the arm's own. LABELLED BEYOND-HUMAN ARM what-if, not a rung.

    MYO_TT_BEYOND=1 TT_ENV=P2 TT_TASK=myo_tt_beyond .venv-myo/bin/python scratchpad/tt2/diag_stale.py --params P --controller C --seeds 98000:98100 --out out/tt2/x.jsonl
"""
import argparse, json, os, sys, time
HERE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(HERE, "playground"))
os.environ.setdefault("TT_ENV", "P2")
os.environ.setdefault("TT_TASK", "myo_tt_beyond")
for _v in ("OPENBLAS_NUM_THREADS", "OMP_NUM_THREADS", "MKL_NUM_THREADS", "VECLIB_MAXIMUM_THREADS"):
    os.environ.setdefault(_v, "1")


def episode(job):
    import importlib, warnings
    warnings.filterwarnings("ignore")
    import tt_fast
    params, seed, ctl = job
    Task = importlib.import_module("tasks." + os.environ["TT_TASK"]).TASK
    task = Task()
    try:
        sim = tt_fast.make_sim(task, params, seed, controller=ctl)
        b = getattr(sim.u, "beyond", None)
        if b:
            sim.peak = sim.peak / b["strength"]   # the controller is told the official peak forces
        res = sim.run()
        res["stale_peak"] = 1.0 if b else 0.0
    except Exception as e:
        return {"seed": seed, "error": str(e)[:300]}
    res["seed"] = seed
    return res


def main():
    import multiprocessing as mp
    ap = argparse.ArgumentParser()
    ap.add_argument("--params"); ap.add_argument("--controller"); ap.add_argument("--seeds", required=True)
    ap.add_argument("--out", required=True); ap.add_argument("--workers", type=int, default=3)
    a = ap.parse_args()
    import tt_fast
    params = tt_fast.read_params(a.params)
    lo, hi = (int(x) for x in a.seeds.split(":"))
    ctl = os.path.abspath(a.controller)
    t0 = time.time()
    with mp.get_context("spawn").Pool(a.workers) as pool, open(a.out, "w") as f:
        for r in pool.imap(episode, [(params, s, ctl) for s in range(lo, hi)], chunksize=1):
            f.write(json.dumps(r, default=float) + "\n"); f.flush()
    rows = [json.loads(l) for l in open(a.out)]
    ok = [r for r in rows if "error" not in r]
    print(json.dumps({"n": len(ok), "errors": len(rows) - len(ok), "solved": sum(1 for r in ok if r.get("solved", 0) > 0), "hit": sum(1 for r in ok if r.get("hit", 0) > 0), "wall_s": round(time.time() - t0)}))


if __name__ == "__main__":
    main()
