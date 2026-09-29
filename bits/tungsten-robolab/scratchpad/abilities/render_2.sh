#!/bin/bash
# Renders the champions promoted on 29 Sep (one at a time). Logs beside each output.
cd /Users/erik/tungsten/bits/tungsten-robolab
P95="ROBOLAB_PROFILE=p95 ROBOLAB_PROFILE_PARTS=strength,speed,tendon,activation"
echo "== long jump one-start champion (5.122 m)"; date
env $P95 .venv/bin/python playground/long_jump_run_render.py long_jump_p95e \
  --params playground/arena/params/long_jump_p95-20260929-043732.txt \
  --controller bin/champions/long_jump_p95-20260929-043732 --seed 0 --out out/long_jump_v7_p95 2>&1 | tail -3 | cut -c1-600
echo "== long jump robust champion (seed 401)"; date
env $P95 .venv/bin/python playground/long_jump_run_render.py long_jump_p95g \
  --params playground/arena/params/long_jump_p95_robust-20260929-034646.txt \
  --controller bin/champions/long_jump_p95_robust-20260929-034646 --seed 401 --out out/long_jump_v7_p95_robust 2>&1 | tail -3 | cut -c1-600
echo "== sprint v4 P95 champion"; date
env ROBOLAB_CALIB=v4 $P95 ROBOLAB_CONTROLLER=bin/champions/sprint_top_speed_v4_p95-20260929-042937 .venv/bin/python playground/bridge.py run_v4 \
  --params playground/arena/params/sprint_top_speed_v4_p95-20260929-042937.txt --seconds 26 --video out/sprint_v4_p95.mp4 2>&1 | tail -3 | cut -c1-500
echo "== done"; date
