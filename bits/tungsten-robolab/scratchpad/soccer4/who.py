import sys, os
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
from myo_bridge import MyoSim
from tasks.myo_soccer import MyoSoccerTask
import mujoco, numpy as np
print(MyoSim.__init__.__code__.co_varnames[:3])
os.environ["MYO_SOCCER_ENV"]="myoChallengeSoccerP1-v0"
sim = MyoSim(MyoSoccerTask(), params={}, seed=700)
m=sim.m
print({s: [m.body(b).name for b in ids] for s, ids in sim.feet.items()})
sim.start_controller()
for k in range(140):
    act, c = sim.tick()
    sim.env.step(sim.action_from(act))
d = sim.d
for i in range(d.ncon):
    con = d.contact[i]
    b1, b2 = m.geom_bodyid[con.geom1], m.geom_bodyid[con.geom2]
    print(m.body(b1).name, m.geom(con.geom1).name, "|", m.body(b2).name, m.geom(con.geom2).name)
sim.stop_controller()
