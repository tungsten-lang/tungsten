import os, sys, numpy as np
sys.path.insert(0, "playground"); sys.path.insert(0, "playground/tasks")
from bridge import Sim
from dribble_btl import DribbleBtlTask
def load(p):
    out = {}
    for line in open(p):
        t = line.split()
        if len(t) >= 2 and not line.startswith("#"): out[t[0]] = float(t[1])
    return out
pfile, seed, lo, hi, over, ctl = sys.argv[1], int(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4]), sys.argv[5], sys.argv[6]
side = sys.argv[7] if len(sys.argv) > 7 else "r"
t = DribbleBtlTask(); t.body_kind = "v3"; t.seed = seed
params = load(pfile); params.update({k: float(v) for k, v in (kv.split("=") for kv in over.split(",") if kv)})
sim = Sim(t, params=params, controller=ctl)
orig = sim.tick
def tick():
    out = orig(); d = sim.d
    if lo <= d.time <= hi and int(round(d.time * 200)) % 2 == 0:
        lab = [x for x in sim.label.split("|") if x.startswith("right" if side == "r" else "left")][0]
        print(f"{d.time:.2f} {lab:18s} ball {d.body('ball').xpos.round(2)} palm {d.site(side+'_palm').xpos.round(2)} wrist {d.body(side+'_hand').xpos.round(2)} elbow {d.body(side+'_forearm').xpos.round(2)} shoulder {d.body(side+'_upper_arm').xpos.round(2)}")
    return out
sim.tick = tick
sim.run(hi + 0.01)
