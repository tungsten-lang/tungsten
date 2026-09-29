"""Identity and effect test of tasks/myo_soccer_ng.py (the nanguard variant) against the official MyoSoccerTask.

usage: test_guard.py --params P --controller C --seed S --seconds T [--modes official,ng0,ng1]
Each mode is a full rollout (same seed). Prints per mode: result metrics (stand_time, bal1_raw, fallen, t_fall), the nan_* counters, and a hash of the
final stepped MjData state (mj_getState INTEGRATION), then whether the modes agree bit for bit."""
import argparse, hashlib, json, os, sys, time
HERE = "/Users/erik/tungsten/bits/tungsten-robolab"
sys.path.insert(0, os.path.join(HERE, "playground"))
sys.path.insert(0, os.path.join(HERE, "scratchpad", "soccer4"))
os.environ.setdefault("MYO_SOCCER_ENV", "myoChallengeSoccerP2-v0")
os.environ.setdefault("MYO_SOCCER_MAX_TIME", "310")
import numpy as np, mujoco
from search4 import read_params
from myo_bridge import MyoSim
from tasks.myo_soccer import MyoSoccerTask
from tasks.myo_soccer_ng import NanGuardSoccerTask

ap = argparse.ArgumentParser()
ap.add_argument("--params", required=True); ap.add_argument("--controller", required=True)
ap.add_argument("--seed", type=int, required=True); ap.add_argument("--seconds", type=float, required=True)
ap.add_argument("--modes", default="official,ng0,ng1")
a = ap.parse_args()
params = read_params(a.params); ctl = os.path.abspath(a.controller)
mujoco.set_mju_user_warning(lambda msg: print("   MUJOCO:", msg, flush=True))
hashes = {}
rows = {}
for mode in a.modes.split(","):
    os.environ["MYO_SOCCER_NANGUARD"] = "0" if mode == "ng0" else "1"
    T = MyoSoccerTask if mode == "official" else NanGuardSoccerTask
    t0 = time.time()
    sim = MyoSim(T(), params=params, controller=ctl, seed=a.seed)
    res = sim.run(a.seconds)
    d = sim.u.robot.mj_data
    st = np.zeros(mujoco.mj_stateSize(sim.m, int(mujoco.mjtState.mjSTATE_INTEGRATION)))
    mujoco.mj_getState(sim.m, d, st, int(mujoco.mjtState.mjSTATE_INTEGRATION))
    h = hashlib.sha1(st.tobytes()).hexdigest()[:16]
    keep = {k: res.get(k) for k in ("time", "stand_time", "bal1_raw", "bal1_300", "fallen", "t_fall", "nan_events", "nan_nudged", "nan_other", "nan_first_t", "nan_tendons", "hold20")}
    hashes[mode] = h
    rows[mode] = {k: v for k, v in res.items() if isinstance(v, (int, float, bool, str)) or v is None}
    print(f"{mode:9s} seed {a.seed} {a.seconds:g} s  state {h}  {json.dumps(keep)}  ({time.time() - t0:.0f} s)", flush=True)
modes = list(hashes)
print("final states identical:", {m: hashes[m] == hashes[modes[0]] for m in modes})
def same(m1, m2):
    skip = {"nan_events", "nan_nudged", "nan_other", "nan_first_t", "nan_tendons", "hold20"}
    return all(rows[m1].get(k) == rows[m2].get(k) for k in rows[m1] if k not in skip)
print("official metrics reproduced:", {m: same(modes[0], m) for m in modes})
