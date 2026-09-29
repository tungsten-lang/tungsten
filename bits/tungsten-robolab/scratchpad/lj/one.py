"""One rollout with the controller's dbg: lines and a per-tick trace of the labels (scratch, mine)."""
import os, sys, json
os.environ.setdefault("MUJOCO_GL", "cgl")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
import importlib
import arena
from bridge import Sim
trial_name, task_name, ctl, params_path, seed = sys.argv[1:6]
extra = dict(kv.split("=") for kv in (sys.argv[6] if len(sys.argv) > 6 else "").split(",") if kv)
trials = arena.load_json(arena.TRIALS, {})
trial = trials[trial_name]
for k, v in trial.get("env", {}).items():
    os.environ[k] = str(v)
task = importlib.import_module(f"tasks.{task_name}").TASK()
task.seed = None if seed == "None" else int(seed)
params = arena.read_params(params_path)
for k, v in extra.items():
    params[k] = float(v)
sim = Sim(task, params=params, controller=os.path.abspath(ctl))
cmds = []
orig = task.on_command
def oc(m, d, cmd):
    cmds.append((round(d.time, 3), cmd))
    return orig(m, d, cmd)
task.on_command = oc
m = sim.run(trial.get("seconds"))
labs = []
last = None
for row in sim.log:
    lab = row[1]
    if lab != last:
        labs.append((round(row[0], 3), lab))
        last = lab
print("labels:", labs[-40:])
for c in cmds:
    if c[1].startswith("dbg:"):
        print(c)
print({k: m.get(k) for k in ("official_m", "effective_m", "board_offset_m", "foul_max_x", "takeoff_vx", "takeoff_vz", "flight_s", "failed", "somersault", "landed_short")})
