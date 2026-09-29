import sys, math, numpy as np, mujoco
sys.path.insert(0, "playground")
from myo_bridge import couple_joints
from myosuite.utils import gym
env = gym.make("myoChallengeSoccerP1-v0"); env.reset(seed=0)
u = env.unwrapped; m, d = u.mj_model, u.mj_data
q0 = m.key_qpos[0].copy()
fe = m.jnt_qposadr[m.joint("flex_extension").id]
root = m.jnt_qposadr[m.joint("root").id]
names = [m.actuator(i).name for i in range(m.nu)]
def quat_mul(a, b):
    w1,x1,y1,z1=a; w2,x2,y2,z2=b
    return np.array([w1*w2-x1*x2-y1*y2-z1*z2, w1*x2+x1*w2+y1*z2-z1*y2, w1*y2-x1*z2+y1*w2+z1*x2, w1*z2+x1*y2-y1*x2+z1*w2])
def state(dp, fv):
    d.qpos[:] = q0; d.qvel[:] = 0
    # pitch the root about world y by dp (positive = forward tilt)
    qr = np.array([math.cos(dp/2), 0, math.sin(dp/2), 0])
    d.qpos[root+3:root+7] = quat_mul(qr, q0[root+3:root+7])
    d.qpos[fe] = fv
    couple_joints(m, d.qpos)
    d.act[:] = 0.0
    mujoco.mj_forward(m, d)
    q1 = d.qpos.copy(); q1[fe] += 1e-4; couple_joints(m, q1)
    J = np.zeros(m.nv)
    for jid in range(m.njnt):
        if m.jnt_type[jid] == 3:
            a = m.jnt_qposadr[jid]; J[m.jnt_dofadr[jid]] = (q1[a] - d.qpos[a]) / 1e-4
    mom = np.zeros((m.nu, m.nv))
    mujoco.mju_sparse2dense(mom, d.actuator_moment, d.moment_rownnz, d.moment_rowadr, d.moment_colind)
    arm = mom @ J
    passive = float(arm @ d.actuator_force)
    cap = 0.0
    for i in range(m.nu):
        if m.actuator_dyntype[i] != mujoco.mjtDyn.mjDYN_MUSCLE: continue
        g = mujoco.mju_muscleGain(d.actuator_length[i], 0.0, m.actuator_lengthrange[i], m.actuator_acc0[i], m.actuator_gainprm[i, :9])
        c = arm[i] * g
        if c > 0: cap += c
    grav = float(d.qfrc_bias @ J)
    pel = d.xmat[m.body("pelvis").id].reshape(3, 3); tor = d.xmat[m.body("torso").id].reshape(3, 3)
    pp = math.atan2(pel[0, 1], pel[2, 1]); tp = math.atan2(tor[0, 1], tor[2, 1])
    need = grav - passive
    return pp, tp, need, cap
print("rows: pelvis pitch offset; cols: flex_extension. cell = need/capacity (tp = thorax pitch)")
fes = [0.4, 0.3, 0.2, 0.1, 0.0, -0.1, -0.2, -0.3, -0.4, -0.5]
print("dp\\fe " + " ".join(f"{f:+10.2f}" for f in fes))
for dp in [0.2, 0.1, 0.0, -0.1, -0.2, -0.3, -0.4]:
    cells = []
    for fv in fes:
        pp, tp, need, cap = state(dp, fv)
        cells.append(f"{need/cap:4.2f}/{tp:+.2f}")
    pp, _, _, _ = state(dp, 0.0)
    print(f"{dp:+.1f} pp{pp:+.2f} " + " ".join(f"{c:>10s}" for c in cells))
