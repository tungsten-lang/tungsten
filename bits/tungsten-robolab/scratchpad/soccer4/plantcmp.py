import os, sys, json, math
import numpy as np
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/soccer4")
os.environ["MYO_SOCCER_ENV"] = "myoChallengeSoccerP2-v0"
from search4 import read_params
from myo_bridge import MyoSim
from tasks.myo_soccer import MyoSoccerTask
ref = json.load(open("playground/tasks/data/soccer_plant_ref.json"))
p = read_params(sys.argv[1]); ctl = os.path.abspath(sys.argv[2])
names = MyoSoccerTask.PLANT_JOINTS
print("ref ", "q", [round(x, 2) for x in ref["q"]], "com", [round(x, 2) for x in ref["com"]], "v", [round(x, 2) for x in ref["vcom"]], "yaw %.2f pitch %.2f" % (ref["yaw"], ref["pitch"]))
for sd in [int(x) for x in sys.argv[3].split(",")]:
    t = MyoSoccerTask()
    r = MyoSim(t, params=p, controller=ctl, seed=sd).run(4.0)
    st = t.plant_st
    if st is None:
        print(sd, "no plant", r.get("stand_time")); continue
    print(sd, "err %.2f" % r.get("plant_err", -1), "q", [round(x, 2) for x in st["q"]], "com", [round(x, 2) for x in st["com"]], "v", [round(x, 2) for x in st["vcom"]], "yaw %.2f pitch %.2f" % (st["yaw"], st["pitch"]), "touch", r.get("t_touch"), "bs", r.get("ball_speed"))
