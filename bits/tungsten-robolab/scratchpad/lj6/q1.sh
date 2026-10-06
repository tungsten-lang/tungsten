#!/bin/sh
# Q1 (SELECTION 31001-31480, LABELLED beyond-human body, unlimited run-up): lever (a) the board and lever (c) the runner with C7's tables UNCHANGED.
#  Cb<d>: JOINT check-mark shift d (m): j_board_shift +d (the planner aims d closer to the line) and ik_gap0 - d (the program sees the same gap error), params/long_jump_beyond_rob2.txt
#  Cn20 : planner-only shift 0.20 (ik_gap0 unchanged)
#  D7   : chain D runner + SB2 + R3 + land_C2 (out/lj6/par_D7.txt) with L3's frozen controller long_jump_run_x-l3b
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
while [ ! -f out/lj6/m1.done ]; do sleep 5; done
rm -f out/lj6/q1.done
C7=params/long_jump_beyond_rob2.txt
CTL=bin/challengers/long_jump_run_y-l4b
G0=2.861114225899115
T=long_jump_v4_beyond_robust96
S=31001-31480
run_shift() { # tag d gap0
  scratchpad/lj6/ev6.sh "$1" $T $C7 $CTL $S 6 --set "j_board_shift=$2,ik_gap0=$3"
}
run_shift Cb10 0.10 2.761114225899115
run_shift Cb20 0.20 2.661114225899115
run_shift Cb30 0.30 2.561114225899115
scratchpad/lj6/ev6.sh D7 $T out/lj6/par_D7.txt bin/challengers/long_jump_run_x-l3b $S 6
run_shift Cb15 0.15 2.711114225899115
run_shift Cb25 0.25 2.611114225899115
scratchpad/lj6/ev6.sh Cn20 $T $C7 $CTL $S 6 --set "j_board_shift=0.20"
echo done > out/lj6/q1.done
