#!/bin/sh
# Q1c (SELECTION 31001-31480, LABELLED beyond-human body, unlimited run-up): the JOINT check-mark shift scan on C7 (j_board_shift +d and ik_gap0 - d), chain D with C7's tables, then the harness calibration.
# (planner-only shifts were tried at d = 0.10: no gain, vz falls 3.86 -> 3.70; the rest of that scan was cancelled.)
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
rm -f out/lj6/q1c.done
C7=params/long_jump_beyond_rob2.txt
CTL=bin/challengers/long_jump_run_y-l4b
T=long_jump_v4_beyond_robust96
S=31001-31480
G0=2.861114225899115
shift() { # tag d
  g=$(python3 -c "print(repr($G0 - $2))")
  scratchpad/lj6/ev6.sh "$1" $T $C7 $CTL $S 6 --set "j_board_shift=$2,ik_gap0=$g"
}
shift Cb20 0.20
shift Cb30 0.30
shift Cb15 0.15
shift Cb25 0.25
scratchpad/lj6/ev6.sh D7 $T out/lj6/par_D7.txt bin/challengers/long_jump_run_x-l3b $S 6
scratchpad/lj6/ev6l.sh calC7 $T $C7 $CTL out/lj6/held711_seeds.txt 6
echo done > out/lj6/q1c.done
