#!/bin/sh
# ideal-control what-ifs from the nominal A2_m495 pen state (am_nom), 60k evals each, init = lean_m495_ideal (L2), 4 workers:
#   base: unchanged; dv04 / dv08: the whole body 0.4 / 0.8 m/s faster at the penultimate touchdown; str120 / str140: muscles 20 / 40 % stronger (the jumper's own 1.5 -> 1.8 / 2.1)
cd /Users/erik/tungsten/bits/tungsten-robolab
export ROBOLAB_CALIB=v4 ROBOLAB_PROFILE=p95 ROBOLAB_PROFILE_PARTS=strength,speed,tendon,activation ROBOLAB_LJ_APPROACH=44
I=out/long_jump_limits/lean_m495_ideal.json
.venv/bin/python playground/long_jump_limits.py optimise am_nom --evals 60000 --workers 2 --lmax=-1.5 --tag base60 --init $I > out/long_jump_limits/am_nom_base60.log 2>&1
ROBOLAB_LJ_DV=0.4 .venv/bin/python playground/long_jump_limits.py optimise am_nom --evals 60000 --workers 2 --lmax=-1.5 --tag dv04 --init $I > out/long_jump_limits/am_nom_dv04.log 2>&1
ROBOLAB_LJ_DV=0.8 .venv/bin/python playground/long_jump_limits.py optimise am_nom --evals 60000 --workers 2 --lmax=-1.5 --tag dv08 --init $I > out/long_jump_limits/am_nom_dv08.log 2>&1
ROBOLAB_LJ_STRENGTH=1.8 .venv/bin/python playground/long_jump_limits.py optimise am_nom --evals 60000 --workers 2 --lmax=-1.5 --tag str120 --init $I > out/long_jump_limits/am_nom_str120.log 2>&1
ROBOLAB_LJ_STRENGTH=2.1 .venv/bin/python playground/long_jump_limits.py optimise am_nom --evals 60000 --workers 2 --lmax=-1.5 --tag str140 --init $I > out/long_jump_limits/am_nom_str140.log 2>&1
echo done > out/long_jump_limits/whatif.done
