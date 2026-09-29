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
    ctl, params, seed, secs = job
    from bridge import Sim
    from dribble_btl import DribbleBtlTask
    t = DribbleBtlTask(); t.body_kind = "v3"; t.seed = seed
    r = Sim(t, params=params, controller=ctl).run(secs)
    keep = ("btl_rate","btl_ok","btl_opportunities","btl_streak","gate_passes","lost","carry_why","body_hits","controlled_s")
    return seed, {k: r.get(k) for k in keep}, {k[9:]: v for k, v in r.items() if k.startswith("btl_fail_")}, r["btl_log"]
if __name__ == "__main__":
    ctl, pfile = sys.argv[1], sys.argv[2]
    over = dict(kv.split("=") for kv in sys.argv[3].split(",")) if len(sys.argv) > 3 and sys.argv[3] else {}
    seeds = [int(s) for s in sys.argv[4].split(",")] if len(sys.argv) > 4 else [1, 2, 3, 4]
    secs = float(sys.argv[5]) if len(sys.argv) > 5 else 15
    params = load(pfile); params.update({k: float(v) for k, v in over.items()})
    ok = opp = 0
    with Pool(min(4, len(seeds))) as p:
        for seed, r, f, log in p.map(run, [(ctl, params, s, secs) for s in seeds]):
            ok += r["btl_ok"]; opp += r["btl_opportunities"]
            print(seed, r, f)
            print("   ", [(e["t"], e["k"], e["why"], e["gate"]) for e in log][:10])
    print("POOLED", ok, "/", opp, round(ok / max(opp, 1), 3))
