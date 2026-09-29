import sys, collections
sys.path.insert(0, "playground"); sys.path.insert(0, "playground/tasks"); sys.path.insert(0, "scratchpad/btl")
from multiprocessing import Pool
from grid import load
def run(job):
    ctl, params, seed, secs = job
    from bridge import Sim
    from dribble_btl import DribbleBtlTask
    t = DribbleBtlTask(); t.body_kind = "v3"; t.seed = seed
    r = Sim(t, params=params, controller=ctl).run(secs)
    return seed, [(e["k"], e["why"]) for e in r["btl_log"]], r["pass_log"]
if __name__ == "__main__":
    params = load(sys.argv[2]); params.update({k: float(v) for k, v in (kv.split("=") for kv in (sys.argv[5] if len(sys.argv) > 5 else "").split(",") if kv)})
    with Pool(2) as p:
        res = p.map(run, [(sys.argv[1], params, s, 8.0) for s in range(int(sys.argv[3]), int(sys.argv[4]))])
    by = collections.defaultdict(collections.Counter)
    for seed, log, pl in res:
        for i, (k, why) in enumerate(log[:4]):
            by[i + 1][why] += 1
    for i in sorted(by): print("pass", i, dict(by[i]))
    arr = [(pl[1]["arrive_xy"], pl[1]["outcome"], pl[1]["gate"], pl[1]["body"]) for _, _, pl in res if len(pl) > 1]
    for a in arr[:12]: print("  return arrive", a)
