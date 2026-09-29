"""Muscle contributions to a joint's torque at given times.
usage: contrib.py <params> <seed> <controller> <joint> <t1,t2,...>"""
import math, os, sys, json
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
seed = int(sys.argv[2]); ctl = sys.argv[3]; jn = sys.argv[4]
times = [float(x) for x in sys.argv[5].split(",")]
class T(MyoSoccerTask):
    def on_step(self, sim, obs, reward, info):
        super().on_step(sim, obs, reward, info)
        m, d = sim.m, sim.d
        t = float(d.time)
        for tt in times:
            if abs(t - tt) < 0.005:
                dof = m.jnt_dofadr[m.joint(jn).id]
                # moment arms: actuator_moment (nu x nv), mujoco>=3 stores sparse; use mj_ functions
                mom = np.zeros((m.nu, m.nv))
                mujoco.mju_sparse2dense(mom, d.actuator_moment, d.moment_rownnz, d.moment_rowadr, d.moment_colind)
                tq = mom[:, dof] * d.actuator_force
                idx = np.argsort(tq)
                q = d.qpos[m.jnt_qposadr[m.joint(jn).id]]
                print(f"t {t:.2f} {jn} q {q:+.3f} total act {tq.sum():+.1f} passive {d.qfrc_passive[dof]:+.1f} constraint {d.qfrc_constraint[dof]:+.1f} bias {d.qfrc_bias[dof]:+.1f} acc {d.qacc[dof]:+.1f} label {sim.label}")
                act = d.act if m.na else d.ctrl
                for i in list(idx[:8]) + list(idx[-6:]):
                    if abs(tq[i]) > 0.5:
                        print(f"   {m.actuator(i).name:14s} tq {tq[i]:+6.1f} arm {mom[i,dof]:+.4f} force {d.actuator_force[i]:+7.1f} act {d.act[i] if m.na else 0:.2f}")
sim = MyoSim(T(), params=params, controller=ctl, seed=seed)
res = sim.run(max(times) + 0.05)
