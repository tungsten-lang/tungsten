"""How well the controller's reference-posture moment arms describe a hip joint's actuation at run time.
usage: addresp.py <params> <seed> <controller> <t1,t2,...>
For each time and each hip joint of the stance (left) leg prints
  Gref  = sum_i a_live_i F_i (a_ref_i / range_i)   (torque per unit contraction offset when the offsets use the reference slopes)
  Glive = sum_i a_live_i F_i (a_live_i / range_i)  (offsets through the live arms)
and the ratio (1 = the reference slopes describe the actuation)."""
import math, os, sys
import numpy as np, mujoco
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
from myo_bridge import MyoSim
from tasks.myo_soccer import MyoSoccerTask
params = {}
for line in open(sys.argv[1]):
    p = line.split()
    if len(p) >= 2 and not line.startswith("#"):
        params[p[0]] = float(p[1])
for kv in os.environ.get("TRACE_SET", "").split(","):
    if "=" in kv:
        k, v = kv.split("="); params[k] = float(v)
seed = int(sys.argv[2]); ctl = sys.argv[3]
times = [float(x) for x in sys.argv[4].split(",")]
JOINTS = ["hip_flexion_l", "hip_adduction_l", "hip_rotation_l", "knee_angle_l", "ankle_angle_l", "subtalar_angle_l"]

def dense_moment(m, d):
    mom = np.zeros((m.nu, m.nv))
    mujoco.mju_sparse2dense(mom, d.actuator_moment, d.moment_rownnz, d.moment_rowadr, d.moment_colind)
    return mom

class T(MyoSoccerTask):
    ref = None
    def on_step(self, sim, obs, reward, info):
        super().on_step(sim, obs, reward, info)
        m, d = sim.m, sim.d
        t = float(d.time)
        if self.ref is None:
            # the reference posture: the reset state
            d2 = mujoco.MjData(m)
            d2.qpos[:] = sim.q_ref if hasattr(sim, "q_ref") else d.qpos
            mujoco.mj_forward(m, d2)
            self.ref = dense_moment(m, d2)
            self.qref = d2.qpos.copy()
        for tt in times:
            if abs(t - tt) < 0.005:
                mom = dense_moment(m, d)
                ids = sim.muscle_ids
                F = m.actuator_gainprm[ids, 2]
                rng = sim.lr[:, 1] - sim.lr[:, 0]
                print(f"t {t:.2f} label {sim.label}")
                for jn in JOINTS:
                    dof = m.jnt_dofadr[m.joint(jn).id]
                    al = mom[ids, dof]
                    ar = self.ref[ids, dof]
                    gref = float(np.sum(al * F * ar / rng))
                    glive = float(np.sum(al * F * al / rng))
                    gref0 = float(np.sum(ar * F * ar / rng))
                    flips = [(m.actuator(ids[k]).name, round(float(ar[k]), 4), round(float(al[k]), 4)) for k in range(len(ids))
                             if ar[k] * al[k] < 0 and abs(ar[k] * F[k] / rng[k]) > 0.02 * abs(gref0) / 6]
                    q = d.qpos[m.jnt_qposadr[m.joint(jn).id]]
                    print(f"  {jn:18s} q {q:+.2f} Gref {gref:9.1f} Glive {glive:9.1f} ratio {gref/glive if glive else 0:+.2f} (at reset Gref0 {gref0:9.1f}) flips {len(flips)}")
sim = MyoSim(T(), params=params, controller=ctl, seed=seed)
sim.run(max(times) + 0.05)
