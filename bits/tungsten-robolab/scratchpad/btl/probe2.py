import os, sys, json
sys.path.insert(0, "playground"); sys.path.insert(0, "playground/tasks")
from multiprocessing import Pool
def load(p, **over):
    out = {}
    for line in open(p):
        t = line.split()
        if len(t) >= 2 and not line.startswith("#"): out[t[0]] = float(t[1])
    out.update(over); return out
def run(job):
    body, ctl, params, seed, secs = job
    from bridge import Sim
    from dribble_btl import DribbleBtlTask
    t = DribbleBtlTask(); t.body_kind = body; t.seed = seed
    r = Sim(t, params=params, controller=ctl).run(secs)
    keep = ("btl_rate","btl_ok","btl_opportunities","btl_attempts","btl_streak","gate_passes","lost","carried","carry_why","max_touch_s","max_up_s","max_both_s","body_hits","x_ok","dribbles")
    return seed, {k: r.get(k) for k in keep}, {k: v for k, v in r.items() if k.startswith("btl_fail_")}, r["btl_log"]
if __name__ == "__main__":
    which = sys.argv[1]
    seeds = range(1, 5)
    if which == "r1m3":
        jobs = [("v1", "bin/challengers/dribble-r1", load("params/dribble_moves.txt", mode=3.0), s, 20) for s in seeds]
    elif which == "r1m2":
        jobs = [("v1", "bin/challengers/dribble-r1", load("params/dribble_moves_x.txt", mode=2.0), s, 15) for s in seeds]
    elif which == "v3m2":
        jobs = [("v3", "bin/robolab_dribble_v3", load("params/dribble_v3_x2.txt", mode=2.0), s, 15) for s in seeds]
    elif which == "v3m3":
        jobs = [("v3", "bin/robolab_dribble_v3", load("params/dribble_v3_x2.txt", mode=3.0), s, 20) for s in seeds]
    elif which == "codex":
        jobs = [("v1", "bin/challengers/codex-dribble_crossover_25", load("params/codex/dribble_crossover_25.txt"), s, 15) for s in seeds]
    with Pool(4) as p:
        for seed, r, f, log in p.map(run, jobs):
            print(seed, r, f)
            print("   ", [(e["k"], e["why"], e["gate"]) for e in log][:14])
