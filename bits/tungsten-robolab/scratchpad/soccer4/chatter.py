"""Per-joint chatter in the hold: RMS of qacc and the lag-1 (one control step) autocorrelation, t in [t0, t1].
usage: chatter.py <params> <controller> <seed> <t0> <t1> [k=v,...]
A lag-1 autocorrelation near -1 is a period-2 (Nyquist) oscillation of the control loop."""
import os, sys
import numpy as np
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/soccer4")
os.environ["MYO_SOCCER_ENV"] = "myoChallengeSoccerP2-v0"
os.environ["MYO_SOCCER_MAX_TIME"] = "310"
import mujoco
from search4 import read_params
from myo_bridge import MyoSim
from tasks.myo_soccer import MyoSoccerTask

params = read_params(sys.argv[1]); ctl = os.path.abspath(sys.argv[2]); seed = int(sys.argv[3]); t0 = float(sys.argv[4]); t1 = float(sys.argv[5])
if len(sys.argv) > 6:
    for kv in sys.argv[6].split(","):
        if "=" in kv:
            k, v = kv.split("="); params[k] = float(v)
qa = []
qv = []
ct = []


class T(MyoSoccerTask):
    def on_step(self, sim, obs, reward, info):
        super().on_step(sim, obs, reward, info)
        d = sim.d
        if t0 <= d.time <= t1:
            qa.append(d.qacc.copy()); qv.append(d.qvel.copy()); ct.append(d.ctrl.copy())


sim = MyoSim(T(), params=params, controller=ctl, seed=seed)
r = sim.run(t1 + 0.05)
m = sim.m
A = np.array(qa); V = np.array(qv); C = np.array(ct)
print("samples", len(A), "result", {k: r.get(k) for k in ("bal1_s", "stand_time", "fallen")})
rows = []
for i in range(A.shape[1]):
    a = A[:, i] - A[:, i].mean()
    rms = float(np.sqrt((a ** 2).mean()))
    ac = float((a[1:] * a[:-1]).mean() / max((a ** 2).mean(), 1e-30))
    j = m.dof_jntid[i]
    rows.append((rms, ac, mujoco.mj_id2name(m, mujoco.mjtObj.mjOBJ_JOINT, j) or f"dof{i}"))
rows.sort(reverse=True)
print("joints by qacc RMS (rad/s^2 or m/s^2), lag-1 autocorrelation:")
for rms, ac, nm in rows[:12]:
    print(f"  {nm:22s} rms {rms:9.3f}  lag1 {ac:+.2f}")
# the muscles whose control alternates the most
cc = C - C.mean(axis=0)
alt = []
for i in range(C.shape[1]):
    c = cc[:, i]
    var = float((c ** 2).mean())
    if var > 1e-12:
        alt.append((var ** 0.5, float((c[1:] * c[:-1]).mean() / var), mujoco.mj_id2name(m, mujoco.mjtObj.mjOBJ_ACTUATOR, i)))
alt.sort(reverse=True)
print("actuators by control RMS (about its mean), lag-1 autocorrelation:")
for rms, ac, nm in alt[:12]:
    print(f"  {nm:14s} rms {rms:8.4f}  lag1 {ac:+.2f}")
