"""The v4 P95 runner through the long jump task with the jump switched off (j_run 1): speed at the board, falls (scratch, mine)."""
import os, sys, json, importlib
os.environ.setdefault("MUJOCO_GL", "cgl")
os.environ["ROBOLAB_PROFILE"] = "p95"; os.environ["ROBOLAB_PROFILE_PARTS"] = "strength,speed,tendon,activation"; os.environ["ROBOLAB_CALIB"] = "v4"
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
import numpy as np
import arena
from bridge import Sim
params_path, ctl, approach = sys.argv[1:4]
seeds = [None if s == "None" else int(s) for s in sys.argv[4].split(",")]
os.environ["ROBOLAB_LJ_APPROACH"] = approach
params = arena.read_params(params_path)
params["j_run"] = 1.0
for s in seeds:
    task = importlib.import_module("tasks.long_jump_v4_p95").TASK()
    task.seed = s
    sim = Sim(task, params=dict(params), controller=os.path.abspath(ctl))
    m = sim.run(task.seconds)
    tr = np.array(task.run_trace)
    x, t = tr[:, 1], tr[:, 0]
    row = []
    for xx in (10, 20, 30, 37.5, 45, 55):
        k = np.searchsorted(x, xx)
        if k >= len(x) - 1: row.append("-"); continue
        lo = np.searchsorted(x, xx - 2.5); hi = min(np.searchsorted(x, xx + 2.5), len(x) - 1)
        row.append("%.2f" % ((x[hi] - x[lo]) / (t[hi] - t[lo])))
    print("seed", s, "fell", m.get("fell_approach"), "max_com_x %.1f" % m.get("max_com_x", 0), "speeds at x=10,20,30,37.5,45,55:", row, flush=True)
