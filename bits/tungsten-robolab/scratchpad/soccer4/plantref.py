"""Record the phase-1 champion's body state at the plant (the chunk entering 'swing')."""
import os, sys, json, math
import numpy as np, mujoco
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
os.environ["MYO_SOCCER_ENV"] = "myoChallengeSoccerP1-v0"
from myo_bridge import MyoSim
from tasks.myo_soccer import MyoSoccerTask
params = {}
for line in open("params/myo_soccer.txt"):
    p = line.split()
    if len(p) >= 2 and not line.startswith("#"):
        params[p[0]] = float(p[1])
ref = {}
class T(MyoSoccerTask):
    def on_step(self, sim, obs, reward, info):
        prev = self.last_label
        super().on_step(sim, obs, reward, info)
        lab = sim.label.split(":")[-1] if sim.label else ""
        if lab == "swing" and "q" not in ref:
            ref.update(self.plant_state(sim))
sim = MyoSim(T(), params=params, controller=os.path.abspath("bin/robolab_myo_soccer"), seed=500)
res = sim.run(4.0)
print({k: res.get(k) for k in ("goal", "t_touch", "ball_speed", "t_plant")})
json.dump(ref, open("playground/tasks/data/soccer_plant_ref.json", "w"), indent=1)
print(json.dumps({k: (v if not isinstance(v, list) else [round(x, 3) for x in v]) for k, v in ref.items()})[:1500])
