import os, sys, json, time
HERE = "/Users/erik/tungsten/bits/tungsten-robolab"
sys.path.insert(0, os.path.join(HERE, "playground")); sys.path.insert(0, os.path.join(HERE, "scratchpad", "soccer4")); sys.path.insert(0, os.path.join(HERE, "scratchpad", "blowup"))
os.environ["MYO_SOCCER_ENV"] = "myoChallengeSoccerP2-v0"; os.environ["MYO_SOCCER_MAX_TIME"] = "310"
import numpy as np, mujoco
from search4 import read_params
from myo_bridge import MyoSim
from tasks.myo_soccer_ng import NanGuardSoccerTask
mujoco.set_mju_user_warning(lambda msg: print("MUJOCO:", msg))
seed = int(sys.argv[1]); secs = float(sys.argv[2])
t0 = time.time()
sim = MyoSim(NanGuardSoccerTask(), params=read_params(os.path.join(HERE, "params/myo_soccer_single_leg_310_shc.txt")), controller=os.path.join(HERE, "bin/challengers/soccer6-p"), seed=seed)
res = sim.run(secs)
print(f"wall {time.time() - t0:.1f} s for {secs} s")
for k, v in res.items():
    if k.startswith(("wrap_", "nan_")) or k in ("stand_time", "bal1_raw", "fallen", "hold20"):
        print(" ", k, v)
