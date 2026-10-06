"""com_shift.py: kinematic COM shift (x, relative to the left ankle) of the whole body for single-joint posture changes from the nominal standing pose (labelled beyond-human body; stance chain fixed)."""
import math, os, sys
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
os.environ["ROBOLAB_CALIB"] = "v4"; os.environ["ROBOLAB_PROFILE"] = "beyond"; os.environ["ROBOLAB_PROFILE_PARTS"] = "strength,speed,tendon,activation"
sys.path.insert(0, os.path.join(ROOT, "playground"))
import mujoco, numpy as np
from practice import load_task
from bridge import Sim
t = load_task("run_v4"); t.seed = None
sim = Sim(t, params={}, controller=os.path.abspath("bin/challengers/run_geary-s5-final"))
m, d = sim.m, sim.d
t.reset(m, d); mujoco.mj_forward(m, d)
pid = m.body("pelvis").id
names = [m.joint(j).name for j in range(m.njnt)]
print("joints:", names)
def foot_pitch():
    R_ = d.xmat[m.body("l_foot").id].reshape(3, 3); return math.atan2(R_[0, 2], R_[2, 2])
def lowz():
    fg = m.geom("l_foot").id; R_ = d.geom_xmat[fg].reshape(3, 3); c = d.geom_xpos[fg]; sz = m.geom_size[fg]
    return min((c + R_ @ np.array([sx * sz[0], 0, sz_ * sz[2]]))[2] for sx in (-1, 1) for sz_ in (-1, 1))
def settle():
    # solve the root pitch so that the left foot is flat, then drop the root so the foot touches the floor
    jp = m.joint("root_pitch").qposadr[0]; jz = m.joint("root_z").qposadr[0]
    x0 = d.qpos[jp]
    for _ in range(30):
        mujoco.mj_forward(m, d); e = foot_pitch()
        if abs(e) < 1e-7: break
        d.qpos[jp] -= e  # first-order: the foot pitch follows the root pitch one to one
    mujoco.mj_forward(m, d)
    d.qpos[jz] -= lowz(); mujoco.mj_forward(m, d)
def com():
    settle()
    return float(d.subtree_com[pid][0]) - float(d.body("l_foot").xpos[0])
# stand pose of the controller: hips 0.05, knees 0.12, ankles -0.05, spine 0.15, shoulders 0, elbows ~2.1
def setj(j, v): d.qpos[m.joint(j).qposadr[0]] = v
def base():
    mujoco.mj_resetData(m, d); t.reset(m, d)
    for s in ("l_", "r_"):
        setj(s+"hip_flex", 0.05); setj(s+"knee", 0.12); setj(s+"ankle", -0.05); setj(s+"shoulder_flex", 0.0); setj(s+"elbow", 2.16)
    setj("spine_flex", 0.15)
    mujoco.mj_forward(m, d)
base(); c0 = com()
print("stand pose COM - left ankle = %+.4f" % c0)
tests = {
 "right hip +0.5": {"r_hip_flex": 0.5}, "right hip +1.0": {"r_hip_flex": 1.0},
 "right hip +1.0, knee +1.0": {"r_hip_flex": 1.0, "r_knee": 1.0},
 "right hip +1.5, knee +1.5": {"r_hip_flex": 1.5, "r_knee": 1.5},
 "both arms +0.8": {"l_shoulder_flex": 0.8, "r_shoulder_flex": 0.8}, "both arms +1.5": {"l_shoulder_flex": 1.5, "r_shoulder_flex": 1.5},
 "arms +1.5 elbows 0.5": {"l_shoulder_flex": 1.5, "r_shoulder_flex": 1.5, "l_elbow": 0.3, "r_elbow": 0.3},
 "spine +0.3": {"spine_flex": 0.45}, "spine +0.6": {"spine_flex": 0.75},
 "both hips +0.3": {"l_hip_flex": 0.35, "r_hip_flex": 0.35},
 "left knee -0.1 (straighter)": {"l_knee": 0.02, "r_knee": 0.02},
 "right leg: hip 1.5 knee 1.5 + arms 1.5": {"r_hip_flex": 1.5, "r_knee": 1.5, "l_shoulder_flex": 1.5, "r_shoulder_flex": 1.5},
}
for k, v in tests.items():
    base()
    for j, val in v.items(): setj(j, val)
    print("%-42s dCOM = %+.4f m" % (k, com() - c0))
