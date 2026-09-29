"""Log the non-ground contacts of the right (swing) leg near the late failure: contactlog.py <params> <seed> <controller> <t0> <t1>"""
import os, sys, math
import numpy as np, mujoco
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/soccer4")
os.environ["MYO_SOCCER_ENV"] = "myoChallengeSoccerP2-v0"
os.environ["MYO_SOCCER_MAX_TIME"] = "310"
from search4 import read_params
from myo_bridge import MyoSim
from tasks.myo_soccer import MyoSoccerTask
p = read_params(sys.argv[1]); seed = int(sys.argv[2]); ctl = os.path.abspath(sys.argv[3]); t0 = float(sys.argv[4]); t1 = float(sys.argv[5])
class T(MyoSoccerTask):
    def on_step(self, sim, obs, reward, info):
        super().on_step(sim, obs, reward, info)
        m, d = sim.m, sim.d
        t = float(d.time)
        if t < t0 or t > t1: return
        k = round(t * 100)
        seen = set()
        for i in range(d.ncon):
            c = d.contact[i]
            b1, b2 = m.geom_bodyid[c.geom1], m.geom_bodyid[c.geom2]
            n1, n2 = m.body(b1).name, m.body(b2).name
            if n1 == "world" or n2 == "world": continue
            f6 = np.zeros(6); mujoco.mj_contactForce(m, d, i, f6)
            key = (n1, n2)
            if key in seen: continue
            seen.add(key)
            print(f"t {t:.2f} contact {n1} - {n2} dist {c.dist:+.4f} force {f6[0]:.1f}")
        if k % 5 == 0:
            r = d.xpos[m.body("calcn_r").id]; l = d.xpos[m.body("calcn_l").id]
            print(f"t {t:.2f} calcn_r z {r[2]:.4f} y {r[1]:.3f} | calcn_l y {l[1]:.3f} | pz {d.xpos[m.body('pelvis').id][2]:.4f}")
sim = MyoSim(T(), params=p, controller=ctl, seed=seed)
r = sim.run(t1 + 0.1)
print("end", r.get("stand_time"), r.get("bal1_s"))
