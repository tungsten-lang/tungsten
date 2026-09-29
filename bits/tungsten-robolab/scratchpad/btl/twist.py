"""Trunk twist trace: python twist.py params seed secs overrides ctl"""
import sys, numpy as np
sys.path.insert(0, "playground"); sys.path.insert(0, "playground/tasks"); sys.path.insert(0, "scratchpad/btl")
from bridge import Sim
from dribble_btl import DribbleBtlTask
from grid import load
pfile, seed, secs, over, ctl = sys.argv[1], int(sys.argv[2]), float(sys.argv[3]), sys.argv[4], sys.argv[5]
t = DribbleBtlTask(); t.body_kind = "v3"; t.seed = seed
params = load(pfile); params.update({k: float(v) for k, v in (kv.split("=") for kv in over.split(",") if kv)})
sim = Sim(t, params=params, controller=ctl)
orig = sim.tick
j = None
def tick():
    global j
    out = orig(); d = sim.d; m = sim.m
    if j is None: j = m.joint("spine_rot")
    if int(round(d.time * 200)) % 4 == 0 and d.time > 1.3:
        lab = [x for x in sim.label.split("|") if x.startswith("trunk") or x.startswith("left") or x.startswith("right")]
        print(f"{d.time:.2f} rot {d.qpos[j.qposadr[0]]:+.3f} w {d.qvel[j.dofadr[0]]:+.2f} lpalm {d.site('l_palm').xpos.round(2)} ball {d.body('ball').xpos.round(2)} {' '.join(lab)}")
    return out
sim.tick = tick
r = sim.run(secs)
print({k: r[k] for k in ("btl_ok", "btl_tried", "btl_streak", "lost")})
