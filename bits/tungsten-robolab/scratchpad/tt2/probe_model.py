"""Read-only probe of the compiled official TT P2 model: actuator types, gain/bias/dyn parameters (agent T2)."""
import os, sys
os.environ.setdefault("TT_ENV", "P2")
HERE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(HERE, "playground"))
import numpy as np, mujoco
from myosuite.utils import gym
env = gym.make("myoChallengeTableTennisP2-v0")
u = env.unwrapped
m = u.mj_model
print("model ids: env.mj_model is robot.mj_model:", u.mj_model is u.robot.mj_model, "| env.mj_data is robot.mj_data:", u.mj_data is u.robot.mj_data)
print("nu", m.nu, "na", m.na, "nv", m.nv, "nq", m.nq, "timestep", m.opt.timestep, "frame_skip", u.frame_skip)
dyn = m.actuator_dyntype; gt = m.actuator_gaintype; bt = m.actuator_biastype
print("dyntype counts", {int(k): int((dyn == k).sum()) for k in np.unique(dyn)})
print("gaintype counts", {int(k): int((gt == k).sum()) for k in np.unique(gt)})
print("biastype counts", {int(k): int((bt == k).sum()) for k in np.unique(bt)})
mus = np.nonzero(dyn == mujoco.mjtDyn.mjDYN_MUSCLE)[0]
oth = np.nonzero(dyn != mujoco.mjtDyn.mjDYN_MUSCLE)[0]
print("muscles", len(mus), "others", [m.actuator(i).name for i in oth])
for i in oth:
    print("  other", m.actuator(i).name, "gaintype", gt[i], "biastype", bt[i], "gainprm", m.actuator_gainprm[i][:4], "biasprm", m.actuator_biasprm[i][:4], "ctrlrange", m.actuator_ctrlrange[i], "forcerange", m.actuator_forcerange[i], m.actuator_forcelimited[i])
print("muscle gaintype set", set(int(x) for x in gt[mus]), "biastype set", set(int(x) for x in bt[mus]))
g = m.actuator_gainprm[mus]; b = m.actuator_biasprm[mus]; d = m.actuator_dynprm[mus]
np.set_printoptions(precision=5, suppress=True, linewidth=200)
print("gainprm cols 0..8 min/max over muscles")
for c in range(9):
    print("  gain[%d]" % c, g[:, c].min(), g[:, c].max(), " bias[%d]" % c, b[:, c].min(), b[:, c].max())
print("gain==bias on cols 0..8:", np.allclose(g[:, :9], b[:, :9]))
print("dynprm cols 0..2 min/max:", [(d[:, c].min(), d[:, c].max()) for c in range(3)])
print("first 3 muscles:", [m.actuator(int(i)).name for i in mus[:3]])
for i in mus[:3]:
    print("  ", m.actuator(int(i)).name, "gain", m.actuator_gainprm[i][:10], "bias", m.actuator_biasprm[i][:10], "dyn", m.actuator_dynprm[i][:3], "lengthrange", m.actuator_lengthrange[i], "acc0", m.actuator_acc0[i], "forcelimited", m.actuator_forcelimited[i], "forcerange", m.actuator_forcerange[i], "actlimited", m.actuator_actlimited[i], m.actuator_actrange[i])
print("actuator_forcelimited any muscle:", bool(m.actuator_forcelimited[mus].any()), " ctrllimited:", bool(m.actuator_ctrllimited[mus].all()), "actearly", bool(m.actuator_actearly[mus].any()))
print("peak (gain[2]) sum", g[:, 2].sum(), "median", np.median(g[:, 2]), "range", g[:, 2].min(), g[:, 2].max())
print("vmax (gain[6]) unique", np.unique(g[:, 6]))
print("tau_act unique", np.unique(d[:, 0]), "tau_deact unique", np.unique(d[:, 1]), "smooth unique", np.unique(d[:, 2]))
print("fpmax unique", np.unique(g[:, 7]), "fvmax unique", np.unique(g[:, 8]), "lmin", np.unique(g[:,4]), "lmax", np.unique(g[:,5]), "scale", np.unique(g[:,3]))
names = [m.actuator(int(i)).name for i in mus]
print("n muscle names", len(names), names[:5])
# which actuators are the two pelvis ones
print("pelvis-ish:", [m.actuator(i).name for i in range(m.nu) if "pelvis" in m.actuator(i).name.lower()])
print("opt: integrator", m.opt.integrator, "cone", m.opt.cone, "solver", m.opt.solver, "iterations", m.opt.iterations, "noslip", m.opt.noslip_iterations, "disableflags", m.opt.disableflags, "enableflags", m.opt.enableflags)
print("actuator_acc0[mus] range", m.actuator_acc0[mus].min(), m.actuator_acc0[mus].max())
