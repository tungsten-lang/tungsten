import os, sys, json, numpy as np
sys.path.insert(0, "playground"); sys.path.insert(0, "playground/tasks")
from bridge import Sim
from dribble_btl import DribbleBtlTask
def load(p, **over):
    out = {}
    for line in open(p):
        t = line.split()
        if len(t) >= 2 and not line.startswith("#"): out[t[0]] = float(t[1])
    out.update(over); return out
body, ctl, pfile, mode, seed, secs = sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4]), int(sys.argv[5]), float(sys.argv[6])
t = DribbleBtlTask(); t.body_kind = body; t.seed = seed
extra = dict(kv.split("=") for kv in sys.argv[7].split(",")) if len(sys.argv) > 7 and sys.argv[7] else {}
params = load(pfile, mode=mode); params.update({k: float(v) for k, v in extra.items()})
sim = Sim(t, params=params, controller=ctl)
rows = []
orig = t.before_step
def hook(m, d):
    orig(m, d)
    if int(round(d.time * 1000)) % 10 == 0 and hasattr(t, "legs"):
        p = d.body("ball").xpos
        cl, cr = t.leg_chain(d, "l"), t.leg_chain(d, "r")
        pl, pr = t.leg_point(cl, p[2]), t.leg_point(cr, p[2])
        g = pr - pl; rel = p[:2] - pl; s = g[0]*rel[1]-g[1]*rel[0]; u = rel @ g / (g @ g)
        rows.append((round(d.time, 2), p.round(2).tolist(), pl.round(2).tolist(), pr.round(2).tolist(), round(float(s), 3), round(float(u), 2),
                     d.body("l_foot").xpos.round(2).tolist(), d.body("r_foot").xpos.round(2).tolist()))
t.before_step = hook
r = sim.run(secs)
for mv in t.moves:
    if mv["type"] != "D": print(mv)
json.dump(rows, open("scratchpad/btl/trace.json", "w"))
lo, hi = float(sys.argv[8]) if len(sys.argv) > 8 else 0, float(sys.argv[9]) if len(sys.argv) > 9 else 99
for row in rows:
    if lo <= row[0] <= hi: print(row)
