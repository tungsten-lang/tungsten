"""Grid over overrides: first-pass arrival mean/std, gate, received, complete BTL, over seeds."""
import sys, itertools, json, numpy as np
sys.path.insert(0, "playground"); sys.path.insert(0, "playground/tasks")
from multiprocessing import Pool
def load(p):
    out = {}
    for line in open(p):
        t = line.split()
        if len(t) >= 2 and not line.startswith("#"): out[t[0]] = float(t[1])
    return out
def run(job):
    ctl, params, seed, secs, tag = job
    from bridge import Sim
    from dribble_btl import DribbleBtlTask
    t = DribbleBtlTask(); t.body_kind = "v3"; t.seed = seed
    r = Sim(t, params=params, controller=ctl).run(secs)
    p0 = r["pass_log"][0] if r["pass_log"] else None
    p1 = r["pass_log"][1] if len(r["pass_log"]) > 1 else None
    return tag, seed, p0, p1, r["btl_ok"]
if __name__ == "__main__":
    ctl, pfile, spec = sys.argv[1], sys.argv[2], json.loads(sys.argv[3])
    seeds = [int(s) for s in sys.argv[4].split(",")] if len(sys.argv) > 4 else list(range(11, 19))
    secs = float(sys.argv[5]) if len(sys.argv) > 5 else 2.6
    base = load(pfile)
    keys = list(spec)
    combos = list(itertools.product(*[spec[k] for k in keys]))
    jobs = []
    for c in combos:
        p = dict(base); p.update(dict(zip(keys, c)))
        jobs += [(ctl, p, s, secs, c) for s in seeds]
    with Pool(4) as pool:
        res = pool.map(run, jobs)
    rows = []
    for c in combos:
        rr = [r for r in res if r[0] == c]
        arr = np.array([r[2]["arrive_xy"] for r in rr if r[2] and r[2]["arrive_xy"]])
        gate = sum(1 for r in rr if r[2] and r[2]["gate"])
        recv = sum(1 for r in rr if r[2] and r[2]["outcome"] == "ok")
        ok1 = sum(1 for r in rr if r[2] and r[2]["ok"])
        ok2 = sum(1 for r in rr if r[3] and r[3]["ok"])
        m = arr.mean(0).round(2).tolist() if len(arr) else None
        sd = arr.std(0).round(2).tolist() if len(arr) else None
        rows.append((ok1, recv, gate, ok2, c, m, sd))
    rows.sort(key=lambda r: (-r[0], -r[1]))
    print("keys", keys)
    for r in rows: print(f"ok1 {r[0]} recv {r[1]} gate {r[2]} ok2 {r[3]}  {r[4]}  arrive {r[5]} sd {r[6]}")
