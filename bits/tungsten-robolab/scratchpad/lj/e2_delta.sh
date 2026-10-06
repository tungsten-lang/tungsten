#!/bin/sh
cd /Users/erik/tungsten/bits/tungsten-robolab
P=params/long_jump_elite2_ik1.txt
BS=$(grep "^j_board_shift" $P | cut -d' ' -f2); G0=$(grep "^ik_gap0" $P | cut -d' ' -f2)
for D in 0.08 0.12; do
  NB=$(python3 -c "print(repr($BS-$D))"); NG=$(python3 -c "print(repr($G0+$D))"); AP=$(python3 -c "print(38.85+$D)")
  export ROBOLAB_LJ_APPROACH=$AP
  echo "== delta $D"
  .venv/bin/python playground/long_jump_eval.py long_jump_elite2_robust --params $P --controller bin/challengers/long_jump_run-b19 --task long_jump_elite2 --seeds 9001-9064,601-616 --workers 2 --set j_board_shift=$NB,ik_gap0=$NG --out out/long_jump_run/e2_delta_$D.json 2>&1 | tail -1 | cut -c1-300
done
