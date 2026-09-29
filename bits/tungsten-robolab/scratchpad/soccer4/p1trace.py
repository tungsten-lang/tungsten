"""Time series of the phase-1 kick under P2 noise (harness as p1probe): usage p1trace.py <noise> <seed> [set]"""
import math, os, sys, json
import numpy as np
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/soccer4")
from search4 import read_params
noise = float(sys.argv[1]); seed = int(sys.argv[2])
os.environ["MYO_SOCCER_ENV"] = "myoChallengeSoccerP2-v0"
import mujoco
from myosuite.utils import gym as mgym
from myo_bridge import MyoSim
from tasks.myo_soccer import MyoSoccerTask
e1 = mgym.make("myoChallengeSoccerP1-v0"); e1.reset(seed=0)
q_p1 = e1.unwrapped.mj_data.qpos.copy()
orig_make = mgym.make
def make2(*a, **k):
    env = orig_make(*a, **k)
    u = env.unwrapped
    orig_grs = u._get_reset_state
    def grs():
        qn, qv = orig_grs()
        m = u.mj_model
        q = q_p1.copy()
        for j in range(m.njnt):
            if m.jnt_type[j] in (2, 3):
                adr = m.jnt_qposadr[j]
                q[adr] = q_p1[adr] + noise * (qn[adr] - q_p1[adr])
        return q, np.zeros_like(qv)
    u._get_reset_state = grs
    return env
mgym.make = make2
p = read_params("/Users/erik/tungsten/bits/tungsten-robolab/playground/arena/params/soccer_p1-20260926-151503.txt")
p["approach"] = 0.0
rows = []
class T(MyoSoccerTask):
    def on_step(self, sim, obs, reward, info):
        super().on_step(sim, obs, reward, info)
        k = round(float(sim.d.time) * 100)
        if k % 3: return
        m, d = sim.m, sim.d
        pel = d.xmat[m.body("pelvis").id].reshape(3, 3)
        com = d.subtree_com[m.body("root").id]
        ct = sim.foot_contacts()
        def q(n): return float(d.qpos[m.jnt_qposadr[m.joint(n).id]])
        rows.append({"t": round(float(d.time), 2), "lab": (sim.label.split(":")[-1] if sim.label else ""), "comx": round(float(com[0]), 3), "comy": round(float(com[1]), 3),
                     "ld_l": round(ct["l"], 2), "ld_r": round(ct["r"], 2), "hl": round(float(d.xpos[m.body("calcn_l").id][0]), 3), "hly": round(float(d.xpos[m.body("calcn_l").id][1]), 3),
                     "hr": round(float(d.xpos[m.body("calcn_r").id][0]), 3), "roll": round(float(pel[2, 2]), 3), "yaw": round(math.atan2(pel[1, 0], pel[0, 0]), 3),
                     "pitch": round(math.atan2(pel[0, 1], pel[2, 1]), 3), "pz": round(float(d.xpos[m.body("pelvis").id][2]), 3),
                     "hfl": round(q("hip_flexion_l"), 2), "kl": round(q("knee_angle_l"), 2), "al": round(q("ankle_angle_l"), 2),
                     "hfr": round(q("hip_flexion_r"), 2), "kr": round(q("knee_angle_r"), 2), "ar": round(q("ankle_angle_r"), 2), "hal": round(q("hip_adduction_l"), 2),
                     "rtx": round(float(d.xpos[m.body("toes_r").id][0]), 3), "rty": round(float(d.xpos[m.body("toes_r").id][1]), 3), "rtz": round(float(d.xpos[m.body("toes_r").id][2]), 3),
                     "bx": round(float(d.xpos[m.body("soccer_ball").id][0]), 3), "by": round(float(d.xpos[m.body("soccer_ball").id][1]), 3), "hfl_r": round(q("hip_flexion_r"), 2)})
sim = MyoSim(T(), params=p, controller="/Users/erik/tungsten/bits/tungsten-robolab/bin/champions/soccer_p1-20260926-151503", seed=seed)
r = sim.run(3.4)
print("goal", r.get("goal"), "ball", r.get("ball_speed"), "fallen", r.get("fallen"), "touch", r.get("t_touch"))
json.dump(rows, open(f"/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/soccer4/tr/p1_{noise}_{seed}.json", "w"))
