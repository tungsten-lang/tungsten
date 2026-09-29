#!/bin/sh
cd /Users/erik/tungsten/bits/tungsten-robolab
export ROBOLAB_CALIB=v4 ROBOLAB_PROFILE=p95 ROBOLAB_PROFILE_PARTS=strength,speed,tendon,activation ROBOLAB_LJ_APPROACH=44
# F3 approach (fin_d 3), nominal start: two starting points, 60k evals each
.venv/bin/python playground/long_jump_limits.py optimise f3_nom --evals 60000 --workers 2 --lmax=-1.5 --tag ideal_a --init out/long_jump_limits/lean_m250_ideal.json > out/long_jump_limits/f3_nom_ideal_a.log 2>&1
.venv/bin/python playground/long_jump_limits.py optimise f3_nom --evals 60000 --workers 2 --lmax=-1.5 --tag ideal_b --init out/long_jump_limits/gp_nom_ideal.json > out/long_jump_limits/f3_nom_ideal_b.log 2>&1
echo done > out/long_jump_limits/f3_ideal.done
