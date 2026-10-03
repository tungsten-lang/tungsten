import sys, importlib, math, os
sys.path.insert(0, "playground")
import numpy as np, mujoco
from bridge import Sim
from search import read_params
params, seed, secs = sys.argv[1], int(sys.argv[2]), float(sys.argv[3])
task = importlib.import_module("tasks.sprint_touch_v4x").TASK(); task.seed = seed
for k, v in dict(objective=3, fly_touch=2, fall_pen=300).items(): setattr(task, k, v)
sim = Sim(task, params=read_params(params), controller="bin/challengers/run_gearx-a")
m = sim.m
J = lambda n: m.jnt_qposadr[mujoco.mj_name2id(m, mujoco.mjtObj.mjOBJ_JOINT, n)]
tid = m.body("torso").id
class R:
    rows = []
    def maybe_capture(self, s):
        d = s.d
        if int(round(d.time / 0.004)) % 25: return
        tu = d.xmat[tid].reshape(3, 3)[:, 2]
        ct = s.contacts()
        self.rows.append((d.time, math.atan2(tu[0], tu[2]), d.qpos[J("root_pitch")], d.qpos[J("l_hip_flex")], d.qpos[J("r_hip_flex")], d.qpos[J("l_knee")], d.qpos[J("r_knee")],
                          d.qvel[m.jnt_dofadr[mujoco.mj_name2id(m, mujoco.mjtObj.mjOBJ_JOINT, "root_x")]], ct["l_foot"], ct["r_foot"]))
r = R(); res = sim.run(secs, recorder=r)
print("fell", res["fell"], "t", round(res["time"], 2))
print("  t    torso pit  pelvis   hipL   hipR  kneeL  kneeR    vx  loadL loadR")
for row in r.rows: print(" %.2f  %7.3f %7.3f %6.2f %6.2f %6.1f %6.1f %6.2f  %.1f  %.1f" % (row[0], row[1], row[2], row[3], row[4], row[5], row[6], row[7], row[8], row[9]))
