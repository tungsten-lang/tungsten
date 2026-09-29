import os, sys, numpy as np
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
envid = sys.argv[1]
os.environ["MYO_SOCCER_ENV"] = envid
import mujoco
from myosuite.utils import gym as mgym
from myo_bridge import MyoSim
from tasks.myo_soccer import MyoSoccerTask
print("task env id", MyoSoccerTask.env_id)
e1 = mgym.make("myoChallengeSoccerP1-v0"); e1.reset(seed=0)
q_p1 = e1.unwrapped.mj_data.qpos.copy()
orig_make = mgym.make
def make2(*a, **k):
    env = orig_make(*a, **k)
    orig_reset = env.reset
    def reset2(*ra, **rk):
        out = orig_reset(*ra, **rk)
        u = env.unwrapped
        d, m = u.mj_data, u.mj_model
        print("after reset: root", d.qpos[7:10])
        d.qpos[:] = q_p1
        d.qvel[:] = 0
        mujoco.mj_forward(m, d)
        if hasattr(u, "obsd_mj_data"):
            u.obsd_mj_data.qpos[:] = q_p1; u.obsd_mj_data.qvel[:] = 0; mujoco.mj_forward(u.obsd_mj_model, u.obsd_mj_data)
        print("after patch: root", d.qpos[7:10])
        return out
    env.reset = reset2
    return env
mgym.make = make2
rec = []
class T(MyoSoccerTask):
    def on_step(self, sim, obs, reward, info):
        super().on_step(sim, obs, reward, info)
        if len(rec) < 3:
            rec.append(sim.d.qpos[7:10].copy()); print("step", len(rec), "root", sim.d.qpos[7:10], "time", sim.d.time)
sim = MyoSim(T(), params={}, controller="/Users/erik/tungsten/bits/champions/none" if False else "/Users/erik/tungsten/bits/tungsten-robolab/bin/champions/soccer_p1-20260926-151503", seed=500)
print("sim root at init", sim.d.qpos[7:10])
r = sim.run(0.05)
