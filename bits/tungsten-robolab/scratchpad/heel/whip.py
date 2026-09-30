"""Passive-whip test: does momentum fold the swing knee if the knee muscles stay out of the way?

    ROBOLAB_CALIB=v4 ROBOLAB_PROFILE=p95 ROBOLAB_PROFILE_PARTS=strength,speed,tendon,activation \
      .venv/bin/python scratchpad/heel/whip.py MODE T0 WIN SEED SECONDS OUT.npz [PARAMS CONTROLLER]

MODE: base       nothing changed
      r_knee_off after each RIGHT toe-off, for WIN s (from T0 s on) every knee muscle of that leg (knee_pos, knee_neg, rf, ham, gas) is set to 0
      r_ext_off  same, but only the knee EXTENSORS (knee_neg, rf) are set to 0
The left leg is the control in the same run.
"""
import sys, importlib
sys.path.insert(0, "playground")
import numpy as np
import mujoco
from bridge import Sim
from search import read_params

mode, T0, WIN, seed, seconds, out = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), int(sys.argv[4]), float(sys.argv[5]), sys.argv[6]
params_path = sys.argv[7] if len(sys.argv) > 7 else "params/run_gearx_v4_p95_x5a.txt"
controller = sys.argv[8] if len(sys.argv) > 8 else "bin/challengers/run_gearx-a"
TAU = 0.0
if mode.startswith("r_tau"):
    TAU = float(mode[5:]); mode = "r_tau"
ZERO = {"base": [], "r_knee_off": ["knee_pos", "knee_neg", "rf", "ham", "gas"], "r_ext_off": ["knee_neg", "rf"], "r_tau": ["knee_pos", "knee_neg", "rf", "ham", "gas"]}[mode]


class SimX(Sim):
    def __init__(self, *a, **k):
        super().__init__(*a, **k)
        self.mi = {mu.name: i for i, mu in enumerate(self.muscles)}
        self.was = {"l": False, "r": False}
        self.lift = {"l": -1.0, "r": -1.0}
        m = self.m
        J = lambda n: mujoco.mj_name2id(m, mujoco.mjtObj.mjOBJ_JOINT, n)
        self.qa = {n: m.jnt_qposadr[J(n)] for n in ("l_knee", "r_knee", "l_hip_flex", "r_hip_flex")}
        self.rows = []
        self.kdof = m.jnt_dofadr[J("r_knee")]
        import os
        for suffix, var in (("_rf", "RF_SCALE"), ("_hip_flex_pos", "HIP_SCALE"), ("_knee_neg", "KN_SCALE"), ("_knee_pos", "KP_SCALE"), ("_ham", "HAM_SCALE")):
            k = float(os.environ.get(var, "1"))
            if k != 1.0:
                for mu in self.muscles:
                    if mu.name.endswith(suffix):
                        a = self.act_ids[self.mi[mu.name]]
                        m.actuator_gainprm[a, 2] *= k; m.actuator_biasprm[a, 2] *= k

    def tick(self):
        act, c = super().tick()
        ct = self.contacts()
        for s in ("l", "r"):
            now = ct[s + "_foot"] > 0.05
            if self.was[s] and not now:
                self.lift[s] = self.d.time
            self.was[s] = now
        if ZERO and self.d.time > T0 and 0 <= self.d.time - self.lift["r"] < WIN:
            for nm in ZERO:
                self.d.ctrl[self.act_ids[self.mi["r_" + nm]]] = 0.0
        d = self.d
        d.qfrc_applied[self.kdof] = TAU if (TAU and d.time > T0 and 0 <= d.time - self.lift["r"] < WIN) else 0.0
        d = self.d
        self.rows.append([d.time, d.qpos[self.qa["l_knee"]], d.qpos[self.qa["r_knee"]], d.qpos[self.qa["l_hip_flex"]], d.qpos[self.qa["r_hip_flex"]],
                          ct["l_foot"], ct["r_foot"], d.qpos[0]])
        return act, c


task = importlib.import_module("tasks.run_v4").TASK()
task.seed = seed
sim = SimX(task, params=read_params(params_path), controller=controller)
res = sim.run(seconds)
A = np.array(sim.rows)
np.save(out, A)
print("fell" if res.get("fell") else "ok", "t", round(A[-1, 0], 1), "peak_speed_1s", round(float(res.get("peak_speed_1s", 0)), 2))
# per toe-off statistics after T0 + 1 s
t = A[:, 0]
for s, kc, hc, fc in (("l", 1, 3, 5), ("r", 2, 4, 6)):
    f = A[:, fc] > 0.05
    offs = [i for i in range(1, len(t)) if f[i - 1] and not f[i] and t[i] > T0 + 1.0]
    pk, tpk, v100 = [], [], []
    for i in offs:
        j = i + int(0.35 / 0.004)
        if j >= len(t): break
        seg = A[i:j, kc]
        pk.append(np.degrees(seg.max())); tpk.append((np.argmax(seg)) * 0.004)
        v100.append(np.degrees(A[i + 25, kc] - A[i, kc]))      # knee flexion gained in the first 0.1 s (deg)
    if pk:
        print(f"{s} leg: {len(pk)} swings  peak knee flexion mean {np.mean(pk):.0f} deg (min {np.min(pk):.0f}, max {np.max(pk):.0f}), "
              f"time to peak {np.mean(tpk):.3f} s, flexion gained in first 0.1 s {np.mean(v100):.0f} deg")
