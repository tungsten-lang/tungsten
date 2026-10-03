import os, sys
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
os.environ["ROBOLAB_CALIB"] = "v4"; os.environ["ROBOLAB_PROFILE"] = "beyond"; os.environ["ROBOLAB_PROFILE_PARTS"] = "strength,speed,tendon,activation"
os.environ["RUN_NATURAL_START"] = "flying"; os.environ["ROBOLAB_SNAP"] = "run_v4_s5s"
sys.path.insert(0, os.path.join(ROOT, "playground"))
from practice import load_task, read_params
from bridge import Sim
kick = float(sys.argv[1])
t = load_task("sprint_touch_v4z"); t.seed = 5; t.fly_touch = 2.0; t.objective = 3.0; t.kick = kick; t.kick_t0 = 1.0; t.kick_t1 = 2.0; t.kick_sign = 1.0
print("task", type(t).__name__, "kick attr", t.kick, "snap", t.snap)
class R:
    def maybe_capture(s, sim):
        pass
sim = Sim(t, params=read_params("scratchpad/sprint5/chains/S1_top.txt"), controller="bin/challengers/run_geary-s5c")
r = sim.run(8.0, recorder=R())
print("kick", kick, "fell", r["fell"], "time", r["time"], "p_max", r.get("p_max"), "kick_done", getattr(t, "_kick_done", None), "kick_time", getattr(t, "_kick_time", None))
