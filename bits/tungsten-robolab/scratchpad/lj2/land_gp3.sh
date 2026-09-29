#!/bin/sh
# one-start landing for the board-relative take-off (nom3): 5 hand-overs, tg from the recorded landing, 2 workers
cd /Users/erik/tungsten/bits/tungsten-robolab
export ROBOLAB_CALIB=v4 ROBOLAB_PROFILE=p95 ROBOLAB_PROFILE_PARTS=strength,speed,tendon,activation ROBOLAB_LJ_APPROACH=44
.venv/bin/python playground/long_jump_limits.py landing --handover hogp3 --capture gp_nom --rec recgp3 --tg ${1:-0.73} --h 0.08 --nk 34 --lz 0.8 --evals 25000 --workers 2 --sigma 0.06 --risk 0.5 --g0 0.3 --out out/long_jump_limits/land_gp3.txt > out/long_jump_limits/land_gp3.log 2>&1
echo done > out/long_jump_limits/land_gp3.done
