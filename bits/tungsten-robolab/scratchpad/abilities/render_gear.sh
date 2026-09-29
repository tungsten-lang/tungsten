#!/bin/bash
# Renders the run_gear four-gear sprinter (sprint_top_speed_v4_p95 champion, 7.907 m/s peak on the arena starts) on the
# v4 P95 body. Seed comes from the task (nominal start).
cd /Users/erik/tungsten/bits/tungsten-robolab
echo "== sprint v4 p95 run_gear champion"; date
env ROBOLAB_CALIB=v4 ROBOLAB_PROFILE=p95 ROBOLAB_PROFILE_PARTS=strength,speed,tendon,activation \
  ROBOLAB_CONTROLLER=bin/challengers/run_gear-v4c .venv/bin/python playground/bridge.py run_v4 \
  --params params/run_gear_v4_p95_g.txt --seconds 26 --video out/sprint_v4_p95_gear4.mp4 2>&1 | tail -4 | cut -c1-500
echo "== done"; date
