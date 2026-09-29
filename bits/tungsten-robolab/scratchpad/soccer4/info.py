import os, sys, numpy as np, mujoco
sys.path.insert(0, "playground")
os.environ["MYO_SOCCER_ENV"]="myoChallengeSoccerP2-v0"
from myo_bridge import MyoSim
from tasks.myo_soccer import MyoSoccerTask
sim = MyoSim(MyoSoccerTask(), params={}, seed=5000)
print("weight N", sim.weight, "dt", sim.u.dt, "horizon", getattr(sim.u, "max_episode_steps", None), sim.env.spec.max_episode_steps if sim.env.spec else None)
print([j[1] for j in sim.joints])
m=sim.m
for n in ["hip_rotation_l","hip_rotation_r","axial_rotation","lat_bending","flex_extension"]:
    try:
        j=m.joint(n); print(n, j.range, "damping", m.dof_damping[m.jnt_dofadr[j.id]], "armature", m.dof_armature[m.jnt_dofadr[j.id]], "stiff", m.jnt_stiffness[j.id])
    except Exception as e: print(n, "missing", e)
# yaw inertia of pelvis+trunk (everything but legs) about vertical through com: approx by composite
mujoco.mj_forward(m, sim.d)
print("root subtree mass", m.body_subtreemass[m.body("root").id] if mujoco.mj_name2id(m, mujoco.mjtObj.mjOBJ_BODY, "root")>=0 else None, sim.root)
