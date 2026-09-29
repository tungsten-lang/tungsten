import sys, numpy as np, mujoco
from myosuite.utils import gym
env = gym.make("myoChallengeSoccerP1-v0"); env.reset(seed=0)
u = env.unwrapped; m, d = u.mj_model, u.mj_data
mujoco.mj_forward(m, d)
F = m.actuator_gainprm[:, 2]
mom = np.zeros((m.nu, m.nv))
mujoco.mju_sparse2dense(mom, d.actuator_moment, d.moment_rownnz, d.moment_rowadr, d.moment_colind)
for jn in ["subtalar_angle_l", "ankle_angle_l", "hip_adduction_l", "hip_rotation_l"]:
    dof = m.jnt_dofadr[m.joint(jn).id]
    t = -mom[:, dof] * F
    pos = t[t > 0].sum(); neg = t[t < 0].sum()
    top = np.argsort(t)
    print(jn, f"max + {pos:.1f} N m, max - {neg:.1f} N m;  - side:", [(m.actuator(i).name, round(t[i],1)) for i in top[:4]], " + side:", [(m.actuator(i).name, round(t[i],1)) for i in top[-4:]])
