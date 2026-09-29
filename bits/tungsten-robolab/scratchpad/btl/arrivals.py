import sys, numpy as np
sys.path.insert(0, "playground"); sys.path.insert(0, "playground/tasks")
from multiprocessing import Pool
def load(p):
    out = {}
    for line in open(p):
        t = line.split()
        if len(t) >= 2 and not line.startswith("#"): out[t[0]] = float(t[1])
    return out
def run(job):
    ctl, params, seed, secs = job
    from bridge import Sim
    from dribble_btl import DribbleBtlTask
    t = DribbleBtlTask(); t.body_kind = "v3"; t.seed = seed
    r = Sim(t, params=params, controller=ctl).run(secs)
    return seed, r["pass_log"], r["move_log"]
if __name__ == "__main__":
    ctl, pfile = sys.argv[1], sys.argv[2]
    over = dict(kv.split("=") for kv in sys.argv[3].split(",")) if len(sys.argv) > 3 and sys.argv[3] else {}
    params = load(pfile); params.update({k: float(v) for k, v in over.items()})
    seeds = [int(s) for s in sys.argv[4].split(",")] if len(sys.argv) > 4 else list(range(11, 19))
    secs = float(sys.argv[5]) if len(sys.argv) > 5 else 2.6
    with Pool(4) as p:
        res = p.map(run, [(ctl, params, s, secs) for s in seeds])
    arr = []
    for seed, pl, ml in res:
        p0 = pl[0] if pl else None
        print(seed, p0 and (p0["gate"], p0["bounce_xy"], p0["arrive_xy"], p0["outcome"]))
        if p0 and p0["arrive_xy"]: arr.append(p0["arrive_xy"])
    a = np.array(arr)
    print("arrival mean", a.mean(0).round(3), "std", a.std(0).round(3), "n", len(a))
