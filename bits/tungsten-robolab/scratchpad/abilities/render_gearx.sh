#!/bin/bash
# Renders the five-gear sprinter (extended-stance gear 5; sprint_top_speed_v4_p95 champion, 8.276 m/s peak on the arena starts) on the v4 P95 body.
cd /Users/erik/tungsten/bits/tungsten-robolab
echo "== sprint v4 p95 five-gear champion"; date
env ROBOLAB_CALIB=v4 ROBOLAB_PROFILE=p95 ROBOLAB_PROFILE_PARTS=strength,speed,tendon,activation \
  ROBOLAB_CONTROLLER=bin/challengers/run_gearx-a .venv/bin/python playground/bridge.py run_v4 \
  --params params/run_gearx_v4_p95_x5a.txt --seconds 26 --video out/sprint_v4_p95_gear5.mp4 2>&1 | tail -4 | cut -c1-500
echo "== done"; date
