import os, sys, numpy as np, mujoco
sys.path.insert(0, "playground")
os.environ["MYO_SOCCER_ENV"]="myoChallengeSoccerP1-v0"
import myosuite  # noqa
from myosuite.utils import gym
env = gym.make("myoChallengeSoccerP1-v0")
env.reset(seed=0)
u = env.unwrapped
pass
m = u.mj_model; d = u.mj_data
for b in ["calcn_l","toes_l","calcn_r","toes_r"]:
    bid = m.body(b).id
    for g in range(m.ngeom):
        if m.geom_bodyid[g]==bid:
            print(b, g, m.geom(g).name, "type", m.geom_type[g], "size", np.round(m.geom_size[g],3), "pos", np.round(m.geom_pos[g],3), "contype", m.geom_contype[g], m.geom_conaffinity[g], "condim", m.geom_condim[g], "fric", m.geom_friction[g])
print("mass", np.sum(m.body_mass))
print("opt", m.opt.cone, m.opt.impratio, m.opt.noslip_iterations)
# floor geom
for g in range(m.ngeom):
    if m.geom_bodyid[g]==0: print("world", g, m.geom(g).name, m.geom_type[g], m.geom_condim[g], m.geom_friction[g], m.geom_contype[g], m.geom_conaffinity[g])
print([ (m.pair_geom1[i], m.pair_geom2[i], m.pair_friction[i], m.pair_dim[i]) for i in range(m.npair)])
