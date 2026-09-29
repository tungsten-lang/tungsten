import sys, numpy as np
sys.path.insert(0, "playground"); sys.path.insert(0, "playground/tasks")
from multiprocessing import Pool
from grid import load
def run(job):
    ctl, params, seed, secs = job
    from bridge import Sim
    from dribble_btl import DribbleBtlTask
    t = DribbleBtlTask(); t.body_kind = "v3"; t.seed = seed
    r = Sim(t, params=params, controller=ctl).run(secs)
    fl = [(round(e[0], 2), round(e[2], 2), round(e[3], 2)) for e in t.events if e[1] == "floor"]
    return seed, r["lost"], [(e["k"], e["why"]) for e in r["btl_log"]], fl[:5], t.zones
if __name__ == "__main__":
    ctl, pfile = sys.argv[1], sys.argv[2]
    params = load(pfile); params.update({k: float(v) for k, v in (kv.split("=") for kv in (sys.argv[3] if len(sys.argv) > 3 else "").split(",") if kv)})
    with Pool(4) as p:
        for seed, lost, log, fl, zones in p.map(run, [(ctl, params, s, 3.5) for s in range(11, 27)]):
            print(seed, lost, log, "floor", fl)
    print("zones", zones)
