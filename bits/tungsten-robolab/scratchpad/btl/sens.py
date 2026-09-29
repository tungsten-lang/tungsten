"""One-at-a-time sweeps around a params file: first-pass ok / received / gate / arrival x over seeds."""
import sys, json, numpy as np
sys.path.insert(0, "scratchpad/btl"); sys.path.insert(0, "playground"); sys.path.insert(0, "playground/tasks")
from multiprocessing import Pool
from grid import load, run
if __name__ == "__main__":
    ctl, pfile, spec = sys.argv[1], sys.argv[2], json.loads(sys.argv[3])
    seeds = [int(s) for s in sys.argv[4].split(",")] if len(sys.argv) > 4 else list(range(11, 19))
    secs = float(sys.argv[5]) if len(sys.argv) > 5 else 2.6
    base = load(pfile)
    jobs = [(ctl, dict(base), s, secs, ("base", 0)) for s in seeds]
    for k, vals in spec.items():
        for v in vals:
            p = dict(base); p[k] = v
            jobs += [(ctl, p, s, secs, (k, v)) for s in seeds]
    with Pool(4) as pool:
        res = pool.map(run, jobs)
    tags = []
    for r in res:
        if r[0] not in tags: tags.append(r[0])
    for tag in tags:
        rr = [r for r in res if r[0] == tag]
        arr = np.array([r[2]["arrive_xy"] for r in rr if r[2] and r[2]["arrive_xy"]])
        ok1 = sum(1 for r in rr if r[2] and r[2]["ok"]); recv = sum(1 for r in rr if r[2] and r[2]["outcome"] == "ok")
        gate = sum(1 for r in rr if r[2] and r[2]["gate"]); ok2 = sum(1 for r in rr if r[3] and r[3]["ok"])
        cur = base.get(tag[0])
        print(f"{tag[0]:>10} {tag[1]:>7} (base {cur if cur is None else round(cur, 3)}): ok1 {ok1} recv {recv} gate {gate} ok2 {ok2}  arrive {arr.mean(0).round(2).tolist() if len(arr) else None} sd {arr.std(0).round(2).tolist() if len(arr) else None}", flush=True)
