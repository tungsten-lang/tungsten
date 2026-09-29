#!/bin/sh
# board-relative ideal for the nominal start of the A1 approach (the one-start trial): D from the line, foot margin 3 cm, init = gp_nom_ideal (foot-based 5.219); usage: <workers>
cd /Users/erik/tungsten/bits/tungsten-robolab
export ROBOLAB_CALIB=v4 ROBOLAB_PROFILE=p95 ROBOLAB_PROFILE_PARTS=strength,speed,tendon,activation ROBOLAB_LJ_APPROACH=44 ROBOLAB_LJ_BOARD=1 ROBOLAB_LJ_MARGIN=0.03
.venv/bin/python playground/long_jump_limits.py optimise gp_nom --evals 150000 --workers ${1:-2} --lmax=-1.5 --tag bd --init out/long_jump_limits/gp_nom_ideal.json > out/long_jump_limits/gp_nom_bd.log 2>&1
echo done > out/long_jump_limits/ideal_gp_board.done
