"""Run a runner champion and log the swing-leg kinematics (knee flexion, heel height, heel-to-hip distance) and leg muscle activations.

    ROBOLAB_CALIB=v4 ROBOLAB_PROFILE=p95 ROBOLAB_PROFILE_PARTS=strength,speed,tendon,activation \
      .venv/bin/python scratchpad/heel/probe.py TASK PARAMS CONTROLLER SEED SECONDS OUT.npz
"""
import sys, importlib, os
sys.path.insert(0, "playground")
import numpy as np
import mujoco
from bridge import Sim
from search import read_params

task_name, params_path, controller, seed, seconds, out = sys.argv[1:7]
task = importlib.import_module(f"tasks.{task_name}").TASK()
task.seed = int(seed)
sim = Sim(task, params=read_params(params_path), controller=controller)
m = sim.m
for suffix, var in (("_rf", "RF_SCALE"), ("_hip_flex_pos", "HIP_SCALE"), ("_knee_neg", "KN_SCALE"), ("_knee_pos", "KP_SCALE"), ("_ham", "HAM_SCALE")):
    k = float(os.environ.get(var, "1"))
    if k != 1.0:
        for i, mu in enumerate(sim.muscles):
            if mu.name.endswith(suffix):
                a = sim.act_ids[i]
                m.actuator_gainprm[a, 2] *= k; m.actuator_biasprm[a, 2] *= k
J = lambda n: mujoco.mj_name2id(m, mujoco.mjtObj.mjOBJ_JOINT, n)
S = lambda n: mujoco.mj_name2id(m, mujoco.mjtObj.mjOBJ_SITE, n)
B = lambda n: mujoco.mj_name2id(m, mujoco.mjtObj.mjOBJ_BODY, n)
qa = lambda n: m.jnt_qposadr[J(n)]
mus = [mu.name for mu in sim.muscles]
want = ["knee_pos", "knee_neg", "rf", "ham", "gas", "hip_flex_pos", "hip_flex_neg"]
cols = [(side, w, mus.index(f"{side}_{w}")) for side in ("l", "r") for w in want]


class Probe:
    def __init__(self):
        self.rows = []

    def maybe_capture(self, s):
        d = s.d
        act = s.log[-1][2]
        pel = d.xpos[B("pelvis")]
        row = [d.time, d.qpos[qa("root_x")], d.qpos[qa("root_z")], d.qpos[qa("root_pitch")],
               d.qpos[qa("l_knee")], d.qpos[qa("r_knee")], d.qpos[qa("l_hip_flex")], d.qpos[qa("r_hip_flex")],
               pel[0], pel[2]]
        for side in ("l", "r"):
            h = d.site_xpos[S(f"{side}_heel")]
            row += [h[0] - pel[0], h[2], h[2] - pel[2]]
        for _, _, i in cols:
            row.append(act[i])
        self.rows.append(row)


pr = Probe()
res = sim.run(float(seconds), recorder=pr)
arr = np.array(pr.rows)
names = (["t", "x", "z", "pitch", "knee_l", "knee_r", "hip_l", "hip_r", "pelvis_x", "pelvis_z",
          "heel_l_dx", "heel_l_z", "heel_l_dz", "heel_r_dx", "heel_r_z", "heel_r_dz"] + [f"{s}_{w}" for s, w, _ in cols])
np.savez(out, arr=arr, names=np.array(names))
print({k: (round(float(v), 3) if isinstance(v, (int, float, np.floating)) else v) for k, v in res.items() if not isinstance(v, (list, dict))})
print("rows", arr.shape)
