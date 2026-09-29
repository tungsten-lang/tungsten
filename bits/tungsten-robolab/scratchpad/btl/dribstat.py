"""Mode 7: the catch dribble's rebound apex and the next pass, over a grid of overrides."""
import sys, itertools, json, numpy as np
sys.path.insert(0, "playground"); sys.path.insert(0, "playground/tasks"); sys.path.insert(0, "scratchpad/btl")
from multiprocessing import Pool
from grid import load
def run(job):
    ctl, params, seed, secs, tag = job
    from bridge import Sim
    from dribble_btl import DribbleBtlTask
    t = DribbleBtlTask(); t.body_kind = "v3"; t.seed = seed
    r = Sim(t, params=params, controller=ctl).run(secs)
    ml = r["move_log"]
    d = next((m for m in ml if not m["pass"]), None)
    p2 = r["pass_log"][1] if len(r["pass_log"]) > 1 else None
    return tag, d and d.get("rise_apex"), bool(p2 and p2["ok"]), r["btl_streak"]
if __name__ == "__main__":
    ctl, pfile, spec = sys.argv[1], sys.argv[2], json.loads(sys.argv[3])
    seeds = range(int(sys.argv[4]), int(sys.argv[5]))
    base = load(pfile); keys = list(spec)
    combos = list(itertools.product(*[spec[k] for k in keys]))
    jobs = []
    for c in combos:
        p = dict(base); p.update(dict(zip(keys, c)))
        jobs += [(ctl, p, s, 6.0, c) for s in seeds]
    with Pool(4) as pool:
        res = pool.map(run, jobs)
    print("keys", keys)
    for c in combos:
        rr = [r for r in res if r[0] == c]
        ap = [r[1] for r in rr if r[1]]
        print(c, f"dribble apex {np.mean(ap):.2f}" if ap else "no dribble", "second pass ok", sum(r[2] for r in rr), "streaks", sorted([r[3] for r in rr], reverse=True)[:4])
