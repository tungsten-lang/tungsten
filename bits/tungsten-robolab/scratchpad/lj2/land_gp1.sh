#!/bin/sh
# one-start landing program for the nominal start (L2): 5 hand-overs (nominal + 4 execution-noise variants of the nom1 take-off), recorded chunk landing as the base, tg 0.73, 4 workers
cd /Users/erik/tungsten/bits/tungsten-robolab
export ROBOLAB_CALIB=v4 ROBOLAB_PROFILE=p95 ROBOLAB_PROFILE_PARTS=strength,speed,tendon,activation ROBOLAB_LJ_APPROACH=44
.venv/bin/python playground/long_jump_limits.py landing --handover hogp --capture gp_nom --rec recgp --tg 0.73 --h 0.08 --nk 34 --lz 0.8 --evals 25000 --workers 4 --sigma 0.06 --risk 0.5 --g0 0.3 --out out/long_jump_limits/land_gp1.txt > out/long_jump_limits/land_gp1.log 2>&1
echo done > out/long_jump_limits/land_gp1.done
