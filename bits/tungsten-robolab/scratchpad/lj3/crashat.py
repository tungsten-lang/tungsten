import os, sys, importlib
os.environ.setdefault("MUJOCO_GL", "cgl")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
import arena
from bridge import Sim
params_path, ctl, task_name, board, seed = sys.argv[1:6]
os.environ.update({"ROBOLAB_CALIB": "v4", "ROBOLAB_PROFILE": "beyond", "ROBOLAB_PROFILE_PARTS": "strength,speed,tendon,activation", "ROBOLAB_LJ_APPROACH": board})
task = importlib.import_module(f"tasks.{task_name}").TASK()
task.seed = None if seed == "None" else int(seed)
sim = Sim(task, params=arena.read_params(params_path), controller=os.path.abspath(ctl))
try:
    sim.run(task.seconds)
except Exception as e:
    print("CRASH after", len(sim.log), "ticks; last entries:")
    for row in sim.log[-6:]:
        print("  t %.3f label %s" % (row[0], row[1]))
