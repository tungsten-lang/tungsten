#!/bin/sh
# board-relative ideals with a shared plant touchdown time (ROBOLAB_LJ_TD 0.268) and a 4 cm foul margin: nominal (gap 2.05) and fast (gap 1.59) starts of the A2_m495 approach
cd /Users/erik/tungsten/bits/tungsten-robolab
export ROBOLAB_CALIB=v4 ROBOLAB_PROFILE=p95 ROBOLAB_PROFILE_PARTS=strength,speed,tendon,activation ROBOLAB_LJ_APPROACH=44 ROBOLAB_LJ_BOARD=1 ROBOLAB_LJ_TD=0.268 ROBOLAB_LJ_TDW=20 ROBOLAB_LJ_MARGIN=0.04
.venv/bin/python playground/long_jump_limits.py optimise am_nom --evals 60000 --workers 2 --lmax=-1.5 --tag bd --init out/long_jump_limits/lean_m495_ideal.json > out/long_jump_limits/am_nom_bd.log 2>&1
.venv/bin/python playground/long_jump_limits.py optimise am_s8010 --evals 60000 --workers 2 --lmax=-1.5 --tag bd --init out/long_jump_limits/am_s8010_idealtd.json > out/long_jump_limits/am_s8010_bd.log 2>&1
echo done > out/long_jump_limits/ideal_board.done
