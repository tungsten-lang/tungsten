"""Sanity check on another skill: the long-jump champion's RUN-UP (approach speed over the last 5 m, speed at 5 m) and take-off on a body, unretuned. The take-off is a near-open-loop program tuned on the exact v4 body, so its distance is expected to fail on another body; the run-up is a closed-loop gear runner."""
import sys, os, importlib, json
sys.path.insert(0, "playground")
from bridge import Sim
from search import read_params
task_name, params, ctl, seed = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
task = importlib.import_module(f"tasks.{task_name}").TASK(); task.seed = seed
sim = Sim(task, params=read_params(params), controller=ctl)
res = sim.run()
keys = ("official_m", "effective_m", "failed", "approach_speed", "speed_5m", "peak_speed_1s_run", "takeoff_vx", "takeoff_vz", "takeoff_angle_deg", "contact_time_s", "board_offset_m", "flight_s", "fell")
print({k: (round(float(res[k]), 3) if k in res and not isinstance(res[k], bool) else res.get(k)) for k in keys})
