#!/bin/sh
cd /Users/erik/tungsten/bits/tungsten-robolab
P=params/long_jump_elite2_ik1.txt
# base shift values
BS=$(grep "^j_board_shift" $P | cut -d' ' -f2); G0=$(grep "^ik_gap0" $P | cut -d' ' -f2)
NB=$(python3 -c "print(repr($BS-0.04))"); NG=$(python3 -c "print(repr($G0+0.04))")
for v in base latch delta latchdelta; do
  case $v in
    base) S="";;
    latch) S="ik_fmin=1.5";;
    delta) S="j_board_shift=$NB,ik_gap0=$NG";;
    latchdelta) S="ik_fmin=1.5,j_board_shift=$NB,ik_gap0=$NG";;
  esac
  if [ -n "$S" ]; then SET="--set $S"; else SET=""; fi
  # the delta variants need the task with the board 0.04 farther: ROBOLAB_LJ_APPROACH
  case $v in delta|latchdelta) export ROBOLAB_LJ_APPROACH=38.89;; *) unset ROBOLAB_LJ_APPROACH;; esac
  echo "== $v"
  .venv/bin/python playground/long_jump_eval.py long_jump_elite2_robust --params $P --controller bin/challengers/long_jump_run-b19 --task long_jump_elite2 --seeds 9001-9064,601-616 --workers 3 $SET 2>&1 | tail -1 | cut -c1-300
done
