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
pfile, seed = sys.argv[1], int(sys.argv[2])
times = [float(x) for x in sys.argv[3].split(",")]
over = dict(kv.split("=") for kv in sys.argv[4].split(",")) if len(sys.argv) > 4 and sys.argv[4] else {}
t = DribbleBtlTask(); t.body_kind = "v3"; t.seed = seed
params = load(pfile); params.update({k: float(v) for k, v in over.items()})
sim = Sim(t, params=params, controller=sys.argv[5] if len(sys.argv) > 5 else "bin/robolab_dribble_btl")
oc = t.on_command
def on_command(m, d, cmd):
    if cmd.startswith("stance_q"): print(cmd)
    return oc(m, d, cmd)
t.on_command = on_command
names = ["hip_flex", "hip_abd", "hip_rot", "knee", "ankle"]
orig = sim.tick
def tick():
    out = orig()
    d = sim.d
    for tt in times:
        if abs(d.time - tt) < 0.0025:
            print(f"t={d.time:.2f} label {sim.label}")
            for s in "lr":
                q = [round(float(d.joint(f"{s}_{n}").qpos[0]), 3) for n in names]
                print(" ", s, "q", q, "knee", d.body(f"{s}_shin").xpos.round(3), "ankle", d.body(f"{s}_foot").xpos.round(3))
            j = sim.m
            for s in "lr":
                qt = []
                for n in names:
                    i = [k for k, mu in enumerate(sim.muscles) if mu.name == f"{s}_{n}_pos"]
                    qt.append(i[0] if i else None)
    return out
sim.tick = tick
sim.run(max(times) + 0.01)
