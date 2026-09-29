#!/bin/sh
# stronger-body what-ifs (muscle peak force x1.2 / x1.4), from the nominal A2_m495 pen state, 60k evals, init lean_m495_ideal, 2 workers
cd /Users/erik/tungsten/bits/tungsten-robolab
export ROBOLAB_CALIB=v4 ROBOLAB_PROFILE=p95 ROBOLAB_PROFILE_PARTS=strength,speed,tendon,activation ROBOLAB_LJ_APPROACH=44
I=out/long_jump_limits/lean_m495_ideal.json
ROBOLAB_LJ_FSCALE=1.2 .venv/bin/python playground/long_jump_limits.py optimise am_nom --evals 60000 --workers 2 --lmax=-1.5 --tag f120 --init $I > out/long_jump_limits/am_nom_f120.log 2>&1
ROBOLAB_LJ_FSCALE=1.4 .venv/bin/python playground/long_jump_limits.py optimise am_nom --evals 60000 --workers 2 --lmax=-1.5 --tag f140 --init $I > out/long_jump_limits/am_nom_f140.log 2>&1
echo done > out/long_jump_limits/whatif2.done
