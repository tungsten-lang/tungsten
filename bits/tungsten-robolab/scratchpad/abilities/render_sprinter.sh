#!/bin/bash
# Renders the labelled sprinter-body champion (sprint_top_speed_v4_sprinter, 8.407 m/s mean peak over 8 fall-free arena starts) on arena start 222 (8.50 m/s peak, fall-free 30 s).
cd /Users/erik/tungsten/bits/tungsten-robolab
echo "== sprint v4 sprinter body, start 222"; date
env ROBOLAB_CALIB=v4 ROBOLAB_PROFILE=sprinter ROBOLAB_PROFILE_PARTS=strength,speed,tendon,activation .venv/bin/python - <<'PY'
import sys, importlib
sys.path.insert(0, "playground")
from bridge import Sim
from search import read_params
import render
task = importlib.import_module("tasks.run_v4").TASK()
task.seed = 222
params = read_params("params/run_gearx_v4_sprinter_g5a.txt")
sim = Sim(task, params=params, controller="bin/challengers/run_gearx-s3a")
rec = render.Recorder(sim)
res = sim.run(26, recorder=rec)
rec.write_mp4("out/sprint_v4_sprinter.mp4")
print({k: (round(v, 3) if isinstance(v, float) else v) for k, v in res.items() if not isinstance(v, (list, dict))})
PY
echo "== done"; date
