#!/bin/sh
cd /Users/erik/tungsten/bits/tungsten-robolab
P=params/long_jump_elite2_ik1.txt
BS=1.15; G0=1.8476524004444563
for D in 0.0 -0.05 -0.10 -0.15; do
  NB=$(python3 -c "print(repr($BS-($D)))"); NG=$(python3 -c "print(repr($G0+($D)))"); AP=$(python3 -c "print(38.85+($D))")
  export ROBOLAB_LJ_APPROACH=$AP
  echo "== delta $D  (board $AP)"
  .venv/bin/python playground/long_jump_eval.py long_jump_elite2_robust32 --params $P --controller bin/challengers/long_jump_run-b20e --task long_jump_elite2 --seeds 9033-9096 --workers 3 --set j_board_shift=$NB,ik_gap0=$NG,j_st_w=0.3 2>&1 | tail -1 | cut -c1-260
done
