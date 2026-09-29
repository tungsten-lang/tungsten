"""Moment arms of the left hip muscles about hip_rotation_l over a posture grid."""
import os, sys, itertools, numpy as np, mujoco
sys.path.insert(0, "playground")
from myosuite.utils import gym
env = gym.make("myoChallengeSoccerP1-v0"); env.reset(seed=0)
u = env.unwrapped; m, d = u.mj_model, u.mj_data
q0 = d.qpos.copy()
def adr(n): return m.jnt_qposadr[m.joint(n).id]
side = sys.argv[1] if len(sys.argv) > 1 else "l"
jr = m.joint("hip_rotation_" + side); dof = m.jnt_dofadr[jr.id]
musc = [i for i in range(m.nu) if m.actuator(i).name.endswith("_" + side)]
grid = list(itertools.product([-0.5, -0.2, 0.1, 0.4], [-0.25, 0.0, 0.25], [-0.6, -0.3, 0.0, 0.3, 0.6]))
A = np.zeros((len(grid), m.nu))
for k, (fl, ad, ro) in enumerate(grid):
    d.qpos[:] = q0
    d.qpos[adr("hip_flexion_" + side)] = fl; d.qpos[adr("hip_adduction_" + side)] = ad; d.qpos[adr("hip_rotation_" + side)] = ro
    mujoco.mj_forward(m, d)
    mom = np.zeros((m.nu, m.nv))
    mujoco.mju_sparse2dense(mom, d.actuator_moment, d.moment_rownnz, d.moment_rowadr, d.moment_colind)
    A[k] = mom[:, dof]
F = m.actuator_gainprm[:, 2]
rows = []
for i in musc:
    a = A[:, i]
    if np.max(np.abs(a)) < 1e-4: continue
    # torque per full activation (pulling, force = -F): tq = -arm * F
    t = -a * F[i]
    rows.append((m.actuator(i).name, t.min(), t.mean(), t.max(), F[i]))
rows.sort(key=lambda r: r[2])
for r in rows: print(f"{r[0]:14s} tq/act min {r[1]:+7.1f} mean {r[2]:+7.1f} max {r[3]:+7.1f}  F {r[4]:.0f}")
