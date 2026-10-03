import sys, importlib, math
sys.path.insert(0, "playground")
import numpy as np, mujoco
from bridge import Sim
from search import read_params
name = sys.argv[1]
task = importlib.import_module("tasks.run_v4").TASK()
sim = Sim(task, params={}, controller="bin/challengers/run_gearx-a")
m, d = sim.m, sim.d
z = np.load(f"playground/cache/sprint_touch_{name}.npz")
tid = m.body("torso").id
out = []
for k in range(len(z["qpos"])):
    d.qpos[:] = z["qpos"][k]; d.qvel[:] = z["qvel"][k]
    mujoco.mj_forward(m, d)
    tu = d.xmat[tid].reshape(3, 3)[:, 2]
    out.append((float(z["vx"][k]), float(z["t"][k]), math.atan2(tu[0], tu[2])))
out.sort()
print(name, "n", len(out), "torso pitch at the snapshot: mean %.3f  min %.3f  max %.3f" % (np.mean([o[2] for o in out]), min(o[2] for o in out), max(o[2] for o in out)))
print(" v(m/s):pitch(rad)@t  ", " ".join("%.2f:%.2f@%.0f" % o for o in out))
