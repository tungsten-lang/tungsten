import os, sys, numpy as np, mujoco
from myosuite.utils import gym
env = gym.make("myoChallengeSoccerP1-v0"); env.reset(seed=0)
u = env.unwrapped; m, d = u.mj_model, u.mj_data
q0 = d.qpos.copy()
def adr(n): return m.jnt_qposadr[m.joint(n).id]
side = "l"
dofs = {k: m.jnt_dofadr[m.joint(k + "_" + side).id] for k in ["hip_flexion", "hip_adduction", "hip_rotation"]}
names = sys.argv[1].split(",")
ids = [m.actuator(n + "_" + side).id for n in names]
F = m.actuator_gainprm[:, 2]
for fl in [-0.4, -0.2, 0.0, 0.3]:
  for ad in [-0.1, 0.1]:
    line = []
    for ro in [-0.6, -0.4, -0.2, 0.0, 0.2, 0.4]:
        d.qpos[:] = q0
        d.qpos[adr("hip_flexion_l")] = fl; d.qpos[adr("hip_adduction_l")] = ad; d.qpos[adr("hip_rotation_l")] = ro
        mujoco.mj_forward(m, d)
        mom = np.zeros((m.nu, m.nv))
        mujoco.mju_sparse2dense(mom, d.actuator_moment, d.moment_rownnz, d.moment_rowadr, d.moment_colind)
        line.append(" ".join(f"{-mom[i, dofs['hip_rotation']] * F[i]:+5.1f}/{-mom[i, dofs['hip_adduction']] * F[i]:+5.0f}" for i in ids))
    print(f"fl {fl:+.1f} ad {ad:+.1f} | " + " | ".join(line))
