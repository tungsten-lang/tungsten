#!/bin/sh
# check-mark shift scan for the robust program on a SELECTION set of fresh seeds (7001-7096): j_board_shift -d and ik_gap0 + d (the planner aims d further back, the program sees the same gap error). L3
cd /Users/erik/tungsten/bits/tungsten-robolab
G0=2.861114225899115
for d in 0.0 0.08 0.15 0.22; do
  gg=$(python3 -c "print($G0+$d)")
  nice -n 15 .venv/bin/python playground/long_jump_eval.py long_jump_v4_beyond --params params/long_jump_beyond_rob1.txt --controller bin/challengers/long_jump_run_x-l3b --task long_jump_v4_beyond_a \
      --seeds 7001-7096 --workers 3 --set j_board_shift=-$d,ik_gap0=$gg --out out/lj3/ev_rob1_shift$d.json > out/lj3/ev_rob1_shift$d.txt 2>&1
  echo "d=$d $(python3 scratchpad/lj3/summ.py out/lj3/ev_rob1_shift$d.json | head -2 | tr '\n' ' ')" >> out/lj3/shiftscan.txt
done
echo done > out/lj3/shiftscan.done
