#!/bin/bash
# Renders the in-representation bat champion of 29 Sep (bat_power_fresh_rep, 25.71 m/s on 24 held-out pitches): contraction knots, reflexes on.
cd /Users/erik/tungsten/bits/tungsten-robolab
echo "== bat_r2-t1 / params/bat_r2_s1.txt"; date
BAT_BODY=athlete BAT_FRESH_PITCH=1 ROBOLAB_CONTROLLER=bin/challengers/bat_r2-t1 .venv/bin/python playground/bridge.py bat \
  --params params/bat_r2_s1.txt --video out/bat_r2_s1.mp4 2>&1 | tail -3 | cut -c1-500
echo "== done"; date
