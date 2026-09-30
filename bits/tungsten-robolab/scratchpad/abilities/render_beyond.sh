#!/bin/bash
# Renders the labelled BEYOND-HUMAN body's arena champion (sprint_top_speed_v4_beyond, chain C, 10.150 m/s mean peak over 9 of 12 starts) on arena start 224 (10.178 m/s peak, stays up 30 s).
cd /Users/erik/tungsten/bits/tungsten-robolab
echo "== sprint v4 beyond-human body, start 224"; date
env ROBOLAB_CALIB=v4 ROBOLAB_PROFILE=beyond ROBOLAB_PROFILE_PARTS=strength,speed,tendon,activation .venv/bin/python - <<'PY'
import sys, importlib
sys.path.insert(0, "playground")
from bridge import Sim
from search import read_params
import render
task = importlib.import_module("tasks.run_v4").TASK()
task.seed = 224
params = read_params("params/run_gearx_v4_beyond_c.txt")
sim = Sim(task, params=params, controller="bin/challengers/run_gearx-s4a")
rec = render.Recorder(sim)
res = sim.run(30, recorder=rec)
rec.write_mp4("out/sprint_v4_beyond.mp4")
print({k: (round(v, 3) if isinstance(v, float) else v) for k, v in res.items() if not isinstance(v, (list, dict))})
PY
echo "== done"; date
