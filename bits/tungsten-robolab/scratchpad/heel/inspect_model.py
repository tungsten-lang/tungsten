import sys, importlib
sys.path.insert(0, "playground")
import numpy as np, mujoco
from bridge import Sim
task = importlib.import_module("tasks.run_v4").TASK()
sim = Sim(task, params={}, controller="bin/challengers/run_gearx-a")
m = sim.m
name = lambda t, i: mujoco.mj_id2name(m, t, i)
print("nv", m.nv, "nu", m.nu, "ntendon", m.ntendon, "opt.timestep", m.opt.timestep)
print("-- joints (right leg + fibres): damping, stiffness, armature")
for j in range(m.njnt):
    n = name(mujoco.mjtObj.mjOBJ_JOINT, j)
    if n.startswith("r_") and ("knee" in n or "hip" in n or "fiber" in n or "ankle" in n):
        dof = m.jnt_dofadr[j]
        print(f"  {n:18s} dof {dof:2d} damping {m.dof_damping[dof]:.3g} stiffness {m.jnt_stiffness[j]:.3g} armature {m.dof_armature[dof]:.3g} range {m.jnt_range[j]} limited {m.jnt_limited[j]}")
print("-- tendons (right): stiffness, damping, range")
for t in range(m.ntendon):
    n = name(mujoco.mjtObj.mjOBJ_TENDON, t)
    if n.startswith("r_"):
        print(f"  {n:24s} stiffness {m.tendon_stiffness[t]:.4g} damping {m.tendon_damping[t]:.4g} lengthspring {m.tendon_lengthspring[t]}")
print("-- bodies (right fibres): mass")
for b in range(m.nbody):
    n = name(mujoco.mjtObj.mjOBJ_BODY, b)
    if n.startswith("r_") and "fiber" in n:
        print(f"  {n:22s} mass {m.body_mass[b]:.4g}")
print("-- actuators (right knee/rf/ham/gas): gainprm, biasprm, dynprm, trn")
for a in range(m.nu):
    n = name(mujoco.mjtObj.mjOBJ_ACTUATOR, a)
    if n.startswith("r_") and any(n.endswith(x) for x in ("knee_pos", "knee_neg", "rf", "ham", "gas")):
        print(f"  {n:14s} gain {np.round(m.actuator_gainprm[a][:9], 3)} bias {np.round(m.actuator_biasprm[a][:4], 3)} dyn {np.round(m.actuator_dynprm[a][:3], 4)} trntype {m.actuator_trntype[a]} trnid {m.actuator_trnid[a]}")
