import os, sys, json
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
os.environ["ROBOLAB_CALIB"] = "v4"; os.environ["ROBOLAB_PROFILE"] = "beyond"; os.environ["ROBOLAB_PROFILE_PARTS"] = "strength,speed,tendon,activation"
sys.path.insert(0, os.path.join(ROOT, "playground"))
import numpy as np, mujoco
from practice import load_task
from bridge import Sim
t = load_task("run_v4")
sim = Sim(t, params={}, controller=os.path.join(ROOT, "bin/challengers/run_geary-s5h"))
out = {}
for seed in range(14001, 14401):
    t.seed = seed
    t.reset(sim.m, sim.d); mujoco.mj_forward(sim.m, sim.d)
    d = sim.d; pid = sim.m.body("pelvis").id
    fx = 0.5 * (float(d.body("l_foot").xpos[0]) + float(d.body("r_foot").xpos[0]))
    com = float(d.subtree_com[pid][0]) - fx
    tu = d.xmat[sim.m.body("torso").id].reshape(3, 3)[:, 2]
    pu = d.xmat[pid].reshape(3, 3)[:, 2]
    out[seed] = (com, float(np.arctan2(tu[0], tu[2])), float(np.arctan2(pu[0], pu[2])))
json.dump(out, open(os.path.join(ROOT, "out/sprint5/initcom.json"), "w"))
print("done", len(out))
