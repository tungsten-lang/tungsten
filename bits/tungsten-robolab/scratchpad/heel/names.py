import sys, importlib, os
sys.path.insert(0, "playground")
import mujoco
from bridge import Sim
task = importlib.import_module("tasks.run_v4").TASK()
sim = Sim(task, params={}, controller="bin/challengers/run_gearx-a")
m = sim.m
print("joints:", [mujoco.mj_id2name(m, mujoco.mjtObj.mjOBJ_JOINT, i) for i in range(m.njnt)])
print("bodies:", [mujoco.mj_id2name(m, mujoco.mjtObj.mjOBJ_BODY, i) for i in range(m.nbody)])
print("sites:", [mujoco.mj_id2name(m, mujoco.mjtObj.mjOBJ_SITE, i) for i in range(m.nsite)][:40])
print("muscles:", [mu.name for mu in sim.muscles])
jn = mujoco.mj_name2id(m, mujoco.mjtObj.mjOBJ_JOINT, "r_knee")
print("r_knee range", m.jnt_range[jn], "damping dof", m.dof_damping[m.jnt_dofadr[jn]] if jn >= 0 else None)
