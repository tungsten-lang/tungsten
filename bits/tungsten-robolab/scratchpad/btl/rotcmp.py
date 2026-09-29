import sys, importlib, numpy as np
sys.path.insert(0, "playground"); sys.path.insert(0, "playground/tasks"); sys.path.insert(0, "scratchpad/btl")
from bridge import Sim
from grid import load
pfile, ctl, over, seed = sys.argv[1:5]
for ov in ("", over):
    t = importlib.import_module("tasks.dribble_btl_v3").TASK(); t.seed = int(seed)
    p = load(pfile); p.update({k: float(v) for k, v in (kv.split("=") for kv in ov.split(",") if kv)})
    sim = Sim(t, params=p, controller=ctl)
    orig = sim.tick; rows = []
    def tick():
        out = orig(); d = sim.d; j = sim.m.joint("spine_rot")
        k = int(round(d.time * 200))
        if k in (40, 100, 200, 250, 300, 360, 400, 460):
            ia = [i for i in range(sim.m.nu) if sim.m.actuator(i).name.startswith("spine_rot")]
            rows.append((round(d.time, 2), round(float(d.qpos[j.qposadr[0]]), 3), [round(float(d.ctrl[i]), 3) for i in ia], [x for x in sim.label.split("|") if x.startswith("trunk") or x.startswith("stance")]))
        return out
    sim.tick = tick
    sim.run(2.35)
    print("==", ov or "base")
    for r in rows: print("  ", r)
