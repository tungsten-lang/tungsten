#!/bin/sh
# ideal-control ceilings of the nominal pen state for three final-approach lean settings (equal conditions: 60k evals, init = gp_nom_ideal)
cd /Users/erik/tungsten/bits/tungsten-robolab
export ROBOLAB_CALIB=v4 ROBOLAB_PROFILE=p95 ROBOLAB_PROFILE_PARTS=strength,speed,tendon,activation ROBOLAB_LJ_APPROACH=44
for t in lean_m495 lean_m250 lean_z000; do
  .venv/bin/python playground/long_jump_limits.py optimise $t --evals 60000 --workers 2 --lmax=-1.5 --tag ideal --init out/long_jump_limits/gp_nom_ideal.json > out/long_jump_limits/${t}_ideal.log 2>&1
done
echo done > out/long_jump_limits/lean_ideal.done
