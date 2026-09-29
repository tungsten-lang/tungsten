import os, sys
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/soccer4")
os.environ["MYO_SOCCER_ENV"] = "myoChallengeSoccerP2-v0"; os.environ["MYO_SOCCER_MAX_TIME"] = "310"
from search4 import read_params
from myo_bridge import MyoSim
from tasks.myo_soccer import MyoSoccerTask
p = read_params("params/myo_soccer_single_leg_310_ramp.txt")
class T(MyoSoccerTask):
    def on_step(self, sim, obs, reward, info):
        super().on_step(sim, obs, reward, info)
        k = round(float(sim.d.time) * 100)
        if k % 40 == 0 and k >= 200:
            pel = sim.d.xmat[sim.m.body("pelvis").id].reshape(3, 3)
            print(f"t {k/100:.1f} pel[2,2] {pel[2,2]:+.3f} pel[1,1] {pel[1,1]:+.3f} pel[2,1] {pel[2,1]:+.3f}")
MyoSim(T(), params=p, controller="bin/challengers/soccer6-i", seed=91044).run(4.0)
