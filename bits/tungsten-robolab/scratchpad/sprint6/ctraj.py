"""ctraj.py PARAMS CTL SEEDS: COM - ankles at 0, 0.1, ... 0.5 s (F1-style stand chunk) for the given seeds."""
import os, sys, math
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
os.environ["ROBOLAB_CALIB"] = "v4"; os.environ["ROBOLAB_PROFILE"] = "beyond"; os.environ["ROBOLAB_PROFILE_PARTS"] = "strength,speed,tendon,activation"
sys.path.insert(0, os.path.join(ROOT, "playground"))
from practice import load_task, read_params
from bridge import Sim
params = read_params(sys.argv[1]); ctl = os.path.abspath(sys.argv[2]); seeds = [int(x) for x in sys.argv[3].split(",")]
class R:
    def __init__(s): s.nx = 0.0; s.rows = []
    def maybe_capture(s, sim):
        d = sim.d
        if d.time < s.nx: return
        s.nx += 0.1
        pid = sim.m.body("pelvis").id
        fx = 0.5 * (float(d.body("l_foot").xpos[0]) + float(d.body("r_foot").xpos[0]))
        s.rows.append(float(d.subtree_com[pid][0]) - fx)
for sd in seeds:
    t = load_task("run_v4"); t.seed = sd
    sim = Sim(t, params=params, controller=ctl); r = R(); res = sim.run(0.62, recorder=r)
    print(sd, " ".join("%+.3f" % x for x in r.rows))
