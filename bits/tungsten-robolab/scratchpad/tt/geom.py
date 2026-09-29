import os, sys, warnings
warnings.filterwarnings("ignore")
os.environ["TT_ENV"]="P2"
sys.path.insert(0,"/Users/erik/tungsten/bits/tungsten-robolab/playground")
import numpy as np, mujoco
from myosuite.utils import gym
env=gym.make("myoChallengeTableTennisP2-v0", normalize_act=True)
u=env.unwrapped
m,d=u.mj_model,u.mj_data
env.reset(seed=1)
mujoco.mj_forward(m,d)
for nm in ["coll_own_half","coll_opponent_half","coll_net","ground","pad","pingpong"]:
    g=m.geom(nm)
    print(nm, "type",g.type, "size",g.size, "pos",d.geom_xpos[g.id], "solref",g.solref, "solimp", g.solimp, "friction", g.friction, "margin",g.margin, "condim", g.condim, "priority", g.priority, "solmix", g.solmix)
    print("   contype",g.contype,"conaffinity",g.conaffinity, "quat/xmat", d.geom_xmat[g.id].reshape(3,3).round(3).tolist())
print("ball mass",m.body("pingpong").mass, "paddle mass", m.body("paddle").mass, "inertia", m.body("paddle").inertia, m.body("paddle").ipos)
print("gravity", m.opt.gravity, "timestep", m.opt.timestep, "dt", u.dt)
print("pelvis pos", d.site_xpos[m.site("pelvis").id])
print("pad geom", d.geom_xpos[m.geom("pad").id], d.geom_xmat[m.geom("pad").id].reshape(3,3)[:,2])
for j in ["pelvis_x","pelvis_y"]:
    jj=m.joint(j); print(j, jj.range, jj.type)
print("paddle body", d.xpos[m.body("paddle").id])
for i in range(m.nu):
    if m.actuator_dyntype[i]!=3:
        print("actuator", m.actuator(i).name, m.actuator_ctrlrange[i], m.actuator_gainprm[i][:3], m.actuator_biasprm[i][:3])
