"""COM speed vs distance for the run-up alone (j_run 1) on a long runway (scratch, mine)."""
import os, sys, json, importlib
os.environ.setdefault("MUJOCO_GL", "cgl")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
import numpy as np
import arena
from bridge import Sim
trial_name, task_name, ctl, params_path, seed, approach = sys.argv[1:7]
os.environ["ROBOLAB_LJ_APPROACH"] = approach
trials = arena.load_json(arena.TRIALS, {})
trial = trials[trial_name]
for k, v in trial.get("env", {}).items():
    os.environ[k] = str(v)
task = importlib.import_module(f"tasks.{task_name}").TASK()
task.seed = None if seed == "None" else int(seed)
params = arena.read_params(params_path)
params["j_run"] = 1.0
params.pop("j_ik", None)
sim = Sim(task, params=params, controller=os.path.abspath(ctl))
m = sim.run(task.seconds)
tr = np.array(task.run_trace)
print("rollout seconds", task.seconds, "trace", tr.shape)
x, v = tr[:, 1], None
# 1 s window speed
t = tr[:, 0]
for xx in (5, 10, 15, 20, 25, 30, 35, 37.5, 40, 42.5, 45, 50, 55, 60, 65):
    k = np.searchsorted(x, xx)
    if k >= len(x) - 1: break
    lo = np.searchsorted(x, xx - 2.5); hi = np.searchsorted(x, xx + 2.5)
    if hi >= len(x): hi = len(x) - 1
    sp = (x[hi] - x[lo]) / (t[hi] - t[lo])
    print("x %5.1f  t %5.2f  speed(5 m window) %5.2f  vx %5.2f" % (xx, t[k], sp, tr[k, 2]))
