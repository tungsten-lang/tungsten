"""The free swing's sweet-spot speed profile (no ball in the way): fire late so the ball has passed, read the bat's own speed timeline.

    .venv/bin/python scratchpad/bat/freeswing.py PARAMS CONTROLLER SEED [k=v,...]
"""
import os, sys
os.environ["BAT_BODY"] = "athlete"
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
import numpy as np
from tasks.bat_rep import BatRepTask
from bridge import Sim


def read_params(path):
    out = {}
    for line in open(path):
        t = line.split()
        if len(t) >= 2 and not line.startswith("#"):
            out[t[0]] = float(t[1])
    return out


params = read_params(sys.argv[1])
for kv in (sys.argv[4] if len(sys.argv) > 4 else "").split(","):
    if kv:
        k, v = kv.split("="); params[k] = float(v)
task = BatRepTask(); task.seed = int(sys.argv[3])
sim = Sim(task, params=params, controller=os.path.abspath(sys.argv[2]))
# a wide-open timeline: record the sweet-spot speed every control tick from the swing's start to 0.5 s later
import mujoco
rows = []
orig = sim.log
class Log(list):
    def append(inner, item):
        list.append(inner, item)
        v = np.zeros(6)
        mujoco.mj_objectVelocity(sim.m, sim.d, mujoco.mjtObj.mjOBJ_SITE, task.site["bat_sweet"], v, 0)
        rows.append((sim.d.time, float(np.linalg.norm(v[3:]))))
sim.log = Log(orig)
m = sim.run(4.6)
r = m["pitches"][0]
ts = r["t_swing"]
print("hit", r["hit"], "t_swing %.3f t_contact/closest %.3f bat_speed %.2f" % (ts, r.get("t_contact", r.get("t_closest")), r["bat_speed"]))
t = np.array([a for a, b in rows]); h = np.array([b for a, b in rows])
k0 = int(np.searchsorted(t, ts)); 
i = int(np.argmax(h[k0:k0 + 100])) + k0
print("free-swing peak %.2f at %.0f ms after the swing start (hips fire)" % (h[i], 1000 * (t[i] - ts)))
for k in range(k0, k0 + 60, 2):
    print("  +%3.0f ms  %.2f" % (1000 * (t[k] - ts), h[k]))
