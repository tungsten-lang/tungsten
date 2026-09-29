"""First-pass stats on fresh seeds: between the legs, caught, complete (incl. the dribble going on), plus returns."""
import sys
sys.path.insert(0, "playground"); sys.path.insert(0, "playground/tasks"); sys.path.insert(0, "scratchpad/btl")
from multiprocessing import Pool
from grid import load
def run(job):
    ctl, params, seed, secs = job
    from bridge import Sim
    from dribble_btl import DribbleBtlTask
    t = DribbleBtlTask(); t.body_kind = "v3"; t.seed = seed
    r = Sim(t, params=params, controller=ctl).run(secs)
    pl = r["pass_log"]
    return seed, pl, r["btl_streak"], r["pass_streak"], r["btl_ok"], r["btl_tried"], r["lost"]
if __name__ == "__main__":
    ctl, pfile, s0, s1, secs, workers = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), float(sys.argv[5]), int(sys.argv[6])
    params = load(pfile)
    params.update({k: float(v) for k, v in (kv.split("=") for kv in (sys.argv[7] if len(sys.argv) > 7 else "").split(",") if kv)})
    with Pool(workers) as p:
        res = p.map(run, [(ctl, params, s, secs) for s in range(s0, s1)])
    n = len(res)
    gate = sum(1 for r in res if r[1] and r[1][0]["gate"]); recv = sum(1 for r in res if r[1] and r[1][0]["outcome"] == "ok")
    ok1 = sum(1 for r in res if r[1] and r[1][0]["ok"]); ok2 = sum(1 for r in res if len(r[1]) > 1 and r[1][1]["ok"])
    ok = sum(r[4] for r in res); tried = sum(r[5] for r in res)
    print(f"n {n}: first pass between legs {gate}, caught {recv}, complete {ok1} ({100*ok1/n:.0f}%); second pass complete {ok2}; "
          f"all passes {ok}/{tried}; btl streaks {sorted([r[2] for r in res], reverse=True)[:6]}; pass streaks max {max(r[3] for r in res)}")
