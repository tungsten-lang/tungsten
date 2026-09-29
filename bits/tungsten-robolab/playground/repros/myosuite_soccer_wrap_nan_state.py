"""Deterministic 1-second reproduction of the soccer hold blow-up from a 7.5 KB saved state (no controller, no arena).

The state is the MjData of MyoSuite's myoChallengeSoccerP2-v0 (the STEPPED data, env.unwrapped.robot.mj_data) after control step 1651 (t = 16.51 s) of
seed 91049 under params/myo_soccer_single_leg_310_shc.txt with bin/challengers/soccer6-p, plus the control of the next control step (10 substeps).
Run with the MyoSuite venv:   .venv-myo/bin/python playground/repros/myosuite_soccer_wrap_nan_state.py [r91049_t16.51.npz | r89122_t15.81.npz | r89134_t134.21.npz | r89135_t130.20.npz | r89130_t141.03.npz]
(all captured with params/myo_soccer_single_leg_310_shc.txt and bin/challengers/soccer6-p; the state is the one after the control step before the failing one)
Prints: the substep at which MuJoCo raises "Nan, Inf or huge value in QACC at DOF 6" (the 8th, t = 16.517 s), the NaN tendon of the position stage
(tendon 239 recfem_r_tendon, before any solver, contact or actuator code runs), and that a 1e-10 rad nudge of the joint angles removes it.
Versions are printed (MuJoCo 3.6.0, MyoSuite 2.12.2, numpy 1.26.4 when recorded). Cause and one-line fix: mujoco_wrap_nan.md in this directory
(engine_util_misc.c, length_circle: `mju_acos(mju_clip(mju_dot(p0n, p1n, 2), -1, 1))`)."""
import os
import sys
import numpy as np
import mujoco

os.environ["MYO_SOCCER_ENV"] = "myoChallengeSoccerP2-v0"
import myosuite
from myosuite.utils import gym

HERE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mujoco_wrap_nan_states")
z = np.load(os.path.join(HERE, sys.argv[1] if len(sys.argv) > 1 else "r91049_t16.51.npz"))
env = gym.make("myoChallengeSoccerP2-v0", max_time_sec=310.0, max_episode_steps=31010)
m = env.unwrapped.mj_model          # the robot's MjData shares this model
spec = int(z["spec"])
print("mujoco", mujoco.__version__, "myosuite", myosuite.__version__, "numpy", np.__version__)

warnings = []
mujoco.set_mju_user_warning(lambda msg: warnings.append(msg))
d = mujoco.MjData(m)
mujoco.mj_setState(m, d, z["state"], spec)
d.ctrl[:] = z["ctrl_fail"]
fail_sub = None
for sub in range(10):
    t0 = float(d.time)
    n0 = len(warnings)
    mujoco.mj_step(m, d)
    if len(warnings) > n0:
        fail_sub = sub
        print(f"substep {sub + 1} of the control step (starting t = {t0:.3f} s): " + " | ".join(w.split(' The simulation')[0] for w in warnings[n0:]))
        break
else:
    print("no warning: the blow-up did not reproduce (different MuJoCo/MyoSuite version?)")
    sys.exit(1)

# the position stage alone at the failing substep's state
d2 = mujoco.MjData(m)
mujoco.mj_setState(m, d2, z["state"], spec)
d2.ctrl[:] = z["ctrl_fail"]
for _ in range(fail_sub):
    mujoco.mj_step(m, d2)
mujoco.mj_fwdPosition(m, d2)     # kinematics + tendon lengths/moments only: no constraint solver, no contacts, no actuator forces
bad = np.flatnonzero(~np.isfinite(d2.ten_length))
print("position stage at t = %.3f s: NaN tendons %s" % (d2.time, [(int(k), mujoco.mj_id2name(m, mujoco.mjtObj.mjOBJ_TENDON, int(k))) for k in bad]))
rng = np.random.default_rng(0)
hs = [m.jnt_qposadr[j] for j in range(m.njnt) if m.jnt_type[j] in (mujoco.mjtJoint.mjJNT_HINGE, mujoco.mjtJoint.mjJNT_SLIDE)]
d2.qpos[hs] += 1e-10 * rng.standard_normal(len(hs))
mujoco.mj_fwdPosition(m, d2)
print("after a 1e-10 rad nudge of every hinge/slide joint: NaN tendons", np.flatnonzero(~np.isfinite(d2.ten_length)).tolist())
