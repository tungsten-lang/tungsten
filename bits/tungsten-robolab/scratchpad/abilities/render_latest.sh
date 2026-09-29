#!/bin/bash
# Renders the newest champions that have no video yet (one at a time). Logs beside each output.
cd /Users/erik/tungsten/bits/tungsten-robolab
P95="ROBOLAB_PROFILE=p95 ROBOLAB_PROFILE_PARTS=strength,speed,tendon,activation"
echo "== long jump p95 champion (4.895 m)"; date
env $P95 .venv/bin/python playground/long_jump_run_render.py long_jump_p95e \
  --params playground/arena/params/long_jump_p95-20260928-064328.txt \
  --controller bin/champions/long_jump_p95-20260928-064328 --seed 0 --out out/long_jump_v5_p95 2>&1 | tail -3
echo "== sprint p95 champion (7.02 m/s)"; date
env $P95 ROBOLAB_CONTROLLER=bin/champions/sprint_top_speed_p95-20260928-035331 .venv/bin/python playground/bridge.py run_v3_p95 \
  --params playground/arena/params/sprint_top_speed_p95-20260928-035331.txt --seconds 26 --video out/sprint_p95_ri.mp4 2>&1 | tail -3 | cut -c1-400
echo "== bat, in robolab's representation (distilled knots, reflexes on)"; date
BAT_BODY=athlete ROBOLAB_CONTROLLER=bin/challengers/bat_v6-knots1 .venv/bin/python playground/bridge.py bat \
  --params params/bat_v6_knots.txt --video out/bat_v6_knots.mp4 2>&1 | tail -3 | cut -c1-400
echo "== done"; date
