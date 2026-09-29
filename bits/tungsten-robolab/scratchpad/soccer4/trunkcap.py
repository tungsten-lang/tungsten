import sys, numpy as np, mujoco
sys.path.insert(0, "playground")
from myo_bridge import couple_joints
from myosuite.utils import gym
env = gym.make("myoChallengeSoccerP1-v0"); env.reset(seed=0)
u = env.unwrapped; m, d = u.mj_model, u.mj_data
q0 = m.key_qpos[0].copy()
fe = m.jnt_qposadr[m.joint("flex_extension").id]
dof = m.jnt_dofadr[m.joint("flex_extension").id]
names = [m.actuator(i).name for i in range(m.nu)]
def torques(fv):
    d.qpos[:] = q0; d.qvel[:] = 0
    d.qpos[fe] = fv
    couple_joints(m, d.qpos)
    d.act[:] = 0.0
    mujoco.mj_forward(m, d)
    # effective generalised torque on the lumbar mode: sum over coupled dofs of qfrc * d(q_dof)/d(fe)
    # approximate by finite difference of the coupling
    q1 = d.qpos.copy(); q1[fe] += 1e-4; couple_joints(m, q1)
    J = np.zeros(m.nv)
    for jid in range(m.njnt):
        if m.jnt_type[jid] == 3:  # hinge
            a = m.jnt_qposadr[jid]; J[m.jnt_dofadr[jid]] = (q1[a] - d.qpos[a]) / 1e-4
    mom = np.zeros((m.nu, m.nv))
    mujoco.mju_sparse2dense(mom, d.actuator_moment, d.moment_rownnz, d.moment_rowadr, d.moment_colind)
    arm = mom @ J
    passive = d.actuator_force.copy()
    tp = arm * passive
    F = m.actuator_gainprm[:, 2]
    # active capacity at act=1: gain from mju_muscleGain
    cap = np.zeros(m.nu)
    for i in range(m.nu):
        if m.actuator_dyntype[i] != mujoco.mjtDyn.mjDYN_MUSCLE: continue
        L = d.actuator_length[i]; lr = m.actuator_lengthrange[i]
        g = mujoco.mju_muscleGain(L, 0.0, lr, m.actuator_acc0[i], m.actuator_gainprm[i, :9])
        cap[i] = arm[i] * g   # force = gain*act (negative), torque = arm*force
    grav = d.qfrc_bias @ J
    rect = [i for i,n in enumerate(names) if n.startswith("rect_abd")]
    ext = cap[cap > 0].sum(); flx = cap[cap < 0].sum()
    return tp.sum(), sum(tp[i] for i in rect), ext, flx, grav
print("fe   passive_total  rect_passive  ext_cap(+)  flex_cap(-)  gravity_bias")
for fv in [0.1, 0.0, -0.1, -0.2, -0.3, -0.4, -0.5, -0.6, -0.8]:
    t = torques(fv)
    print(f"{fv:+.2f}  {t[0]:+8.1f}  {t[1]:+8.1f}  {t[2]:+8.1f}  {t[3]:+8.1f}  {t[4]:+8.1f}")
