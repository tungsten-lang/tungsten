"""Reproduce a MuJoCo blow-up from a saved state and log every physics step around it.
usage: blowdebug.py <params> <controller> <seed> <t_save> <t_end>
Runs the rollout to t_save (a control step), saves qpos/qvel/act/ctrl, keeps the rollout going to t_end (the blow-up), then replays the
saved state with the ctrl held constant for the last ctrl values seen, printing per physics step: the largest inter-body contact
forces (body pair, distance), |qacc|max, the largest efc_force, the number of contacts."""
import os, sys, math
import numpy as np
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/soccer4")
os.environ["MYO_SOCCER_ENV"] = "myoChallengeSoccerP2-v0"
os.environ["MYO_SOCCER_MAX_TIME"] = "310"
import mujoco
from search4 import read_params
from myo_bridge import MyoSim
from tasks.myo_soccer import MyoSoccerTask

params = read_params(sys.argv[1]); ctl = os.path.abspath(sys.argv[2]); seed = int(sys.argv[3]); t_save = float(sys.argv[4]); t_end = float(sys.argv[5])
saved = {}
ctrls = []


class T(MyoSoccerTask):
    def on_step(self, sim, obs, reward, info):
        super().on_step(sim, obs, reward, info)
        d = sim.d
        t = float(d.time)
        if t >= t_save and "qpos" not in saved:
            saved.update(qpos=d.qpos.copy(), qvel=d.qvel.copy(), act=d.act.copy(), ctrl=d.ctrl.copy(), t=t, qacc_warmstart=d.qacc_warmstart.copy())
        if "qpos" in saved:
            ctrls.append((t, d.ctrl.copy()))


sim = MyoSim(T(), params=params, controller=ctl, seed=seed)
try:
    sim.run(t_end)
except Exception as e:
    print("run ended:", e)
m = sim.m
print("saved at", saved.get("t"), "ctrl samples after:", len(ctrls))
d = mujoco.MjData(m)
d.qpos[:] = saved["qpos"]; d.qvel[:] = saved["qvel"]; d.act[:] = saved["act"]; d.time = saved["t"]
d.qacc_warmstart[:] = saved["qacc_warmstart"]
mujoco.mj_forward(m, d)
name = lambda b: m.body(b).name
cut = len(ctrls)
for i in range(1, len(ctrls)):
    if ctrls[i][0] < ctrls[i - 1][0]:
        cut = i
        break
ctrls = ctrls[:cut]
print("ctrl sample times", round(ctrls[0][0], 3), "..", round(ctrls[-1][0], 3), "n", len(ctrls))
hist = []
prev_t = d.time
f6 = np.zeros(6)
done = False
for k, (tc, cc) in enumerate(ctrls[1:]):
    d.ctrl[:] = cc
    for _ in range(10):
        mujoco.mj_step(m, d)
        if d.time < prev_t - 1e-9:
            print("simulation reset (blow-up) at physics step after t =", round(prev_t, 4), "; last 12 steps before it:")
            for row in hist[-12:]:
                print(row)
            done = True
            break
        prev_t = d.time
        qa = float(np.abs(d.qacc).max())
        efc = float(np.abs(d.efc_force).max()) if d.nefc else 0.0
        rows = []
        for i in range(d.ncon):
            c = d.contact[i]
            b1, b2 = m.geom_bodyid[c.geom1], m.geom_bodyid[c.geom2]
            n1, n2 = name(b1), name(b2)
            if n1 == "world" or n2 == "world":
                continue
            mujoco.mj_contactForce(m, d, i, f6)
            rows.append((abs(f6[0]), n1, n2, c.dist))
        rows.sort(reverse=True)
        top = "; ".join(f"{a}-{b} {dist * 1000:+.2f}mm {f:.0f}N" for f, a, b, dist in rows[:3])
        hist.append(f"  t {d.time:8.4f} ncon {d.ncon:3d} |qacc|max {qa:10.3g} efc max {efc:9.3g} | {top}")
    if done:
        break
if not done:
    print("no blow-up reproduced in the replay; last 5 steps:")
    for row in hist[-5:]:
        print(row)
