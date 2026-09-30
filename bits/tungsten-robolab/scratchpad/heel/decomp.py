"""Decompose the swing knee's equation of motion in the champion runner: muscles (active / passive), inertial coupling, gravity+Coriolis, damping.

    ROBOLAB_CALIB=v4 ROBOLAB_PROFILE=p95 ROBOLAB_PROFILE_PARTS=strength,speed,tendon,activation \
      .venv/bin/python scratchpad/heel/decomp.py SEED T_FROM T_TO OUT.npz [PARAMS CONTROLLER]
"""
import sys, importlib
sys.path.insert(0, "playground")
import numpy as np
import mujoco
from bridge import Sim
from search import read_params

seed, t_from, t_to, out = int(sys.argv[1]), float(sys.argv[2]), float(sys.argv[3]), sys.argv[4]
params_path = sys.argv[5] if len(sys.argv) > 5 else "params/run_gearx_v4_p95_x5a.txt"
controller = sys.argv[6] if len(sys.argv) > 6 else "bin/challengers/run_gearx-a"
task = importlib.import_module("tasks.run_v4").TASK(); task.seed = seed
sim = Sim(task, params=read_params(params_path), controller=controller)
m = sim.m
J = lambda n: mujoco.mj_name2id(m, mujoco.mjtObj.mjOBJ_JOINT, n)
dk = m.jnt_dofadr[J("r_knee")]; dh = m.jnt_dofadr[J("r_hip_flex")]
names = [mu.name for mu in sim.muscles]
r_mus = [i for i, n in enumerate(names) if n.startswith("r_") and any(n.endswith(x) for x in ("knee_pos", "knee_neg", "rf", "ham", "gas", "hip_flex_pos", "hip_flex_neg"))]
d2 = mujoco.MjData(m)
FIB = {n: m.jnt_dofadr[J(n)] for n in ("r_knee_neg_fiber", "r_rf_fiber", "r_gas_fiber")}
FIBQ = {n: m.jnt_qposadr[J(n)] for n in FIB}
FIBR = {n: m.jnt_range[J(n)] for n in FIB}
TEN = {n: mujoco.mj_name2id(m, mujoco.mjtObj.mjOBJ_TENDON, n) for n in ("r_knee_neg_see", "r_rf_see", "r_gas_see")}
nv = m.nv
M = np.zeros((nv, nv))


class Rec:
    def __init__(self):
        self.rows = []
        self.was = False
        self.lift = -1.0

    def maybe_capture(self, s):
        d = s.d
        ct = s.contacts()["r_foot"] > 0.05
        if self.was and not ct:
            self.lift = d.time
        self.was = ct
        if not (t_from <= d.time <= t_to):
            return
        mujoco.mj_fullM(m, d, M)
        coup = -(M[dk] @ d.qacc - M[dk, dk] * d.qacc[dk])
        mujoco.mj_copyData(d2, m, d)
        d2.act[:] = 0.0; d2.ctrl[:] = 0.0
        mujoco.mj_forward(m, d2)
        tau_pass_mus = d2.qfrc_actuator[dk]
        mom = np.zeros((m.nu, m.nv))
        mujoco.mju_sparse2dense(mom, d.actuator_moment.reshape(-1), d.moment_rownnz.reshape(-1), d.moment_rowadr.reshape(-1), d.moment_colind.reshape(-1))
        per = [mom[sim.act_ids[i], dk] * d.actuator_force[sim.act_ids[i]] for i in r_mus]
        extra = []
        for n in FIB:
            extra += [d.qpos[FIBQ[n]], d.qvel[FIB[n]], FIBR[n][1] - d.qpos[FIBQ[n]], d.qfrc_constraint[FIB[n]], d.qfrc_passive[FIB[n]], d.qfrc_actuator[FIB[n]]]
        for n, t in TEN.items():
            extra += [d.ten_length[t], m.tendon_stiffness[t] * max(0.0, d.ten_length[t])]
        self.rows.append([d.time, d.time - self.lift, d.qpos[m.jnt_qposadr[J("r_knee")]], d.qvel[dk], d.qacc[dk],
                          d.qpos[m.jnt_qposadr[J("r_hip_flex")]], d.qvel[dh], d.qacc[dh],
                          d.qfrc_actuator[dk], tau_pass_mus, d.qfrc_bias[dk], d.qfrc_passive[dk], d.qfrc_constraint[dk], coup, M[dk, dk], *per, *extra])


rec = Rec()
sim.run(t_to + 0.01, recorder=rec)
A = np.array(rec.rows)
cols = ["t", "since_lift", "knee", "knee_v", "knee_a", "hip", "hip_v", "hip_a", "tau_mus", "tau_mus_passive", "tau_bias", "tau_joint_passive", "tau_constraint", "tau_coupling", "Mkk"] + [names[i] for i in r_mus]
for n in FIB:
    cols += [f"{n}.q", f"{n}.v", f"{n}.room_to_upper_limit", f"{n}.constraint", f"{n}.passive", f"{n}.actuator"]
for n in TEN:
    cols += [f"{n}.length", f"{n}.spring_force"]
np.savez(out, A=A, cols=np.array(cols))
print("rows", A.shape)
