"""Per-seed move chain: python moves.py ctl params s0 s1 secs [overrides]"""
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
    return seed, r
if __name__ == "__main__":
    ctl, pfile, s0, s1, secs = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), float(sys.argv[5])
    params = load(pfile); params.update({k: float(v) for k, v in (kv.split("=") for kv in (sys.argv[6] if len(sys.argv) > 6 else "").split(",") if kv)})
    with Pool(4) as p:
        res = p.map(run, [(ctl, params, s, secs) for s in range(s0, s1)])
    tot = 0
    for seed, r in res:
        chain = []
        for m in r["move_log"]:
            a = m.get("rise_apex"); chain.append(f"{'P' if m['pass'] else 'D'}:{str(m["outcome"])[:8]}@{m['t']:.2f}" + (f"/{a:.2f}" if a else ""))
        tot += r["btl_streak"]
        print(seed, "streak", r["btl_streak"], "ok", r["btl_ok"], "passes", [(round(p["t"], 2), str(p["outcome"])[:10], p.get("rise_apex") and round(p["rise_apex"], 2), p.get("recv_vh") and round(p["recv_vh"], 2), p["ok"]) for p in r["pass_log"]])
        print("    ", " ".join(chain), "|", r.get("lost"), r.get("carry_why"))
    print("mean streak", tot / len(res))
