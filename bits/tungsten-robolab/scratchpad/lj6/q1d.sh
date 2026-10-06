#!/bin/sh
# Q1d (SELECTION 31001-31480; LABELLED beyond-human body, unlimited run-up): the JOINT check-mark shift scan on C7: j_board_shift +d and ik_gap0 - d (params/long_jump_beyond_rob2.txt, l4b)
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
while [ ! -f out/lj6/q1c.done ]; do sleep 5; done
rm -f out/lj6/q1d.done
C7=params/long_jump_beyond_rob2.txt
CTL=bin/challengers/long_jump_run_y-l4b
T=long_jump_v4_beyond_robust96
S=31001-31480
G0=2.861114225899115
runshift() {
  g=$(python3 -c "print(repr($G0 - $2))")
  scratchpad/lj6/ev6.sh "$1" $T $C7 $CTL $S 6 --set "j_board_shift=$2,ik_gap0=$g"
}
runshift Cb20 0.20
runshift Cb30 0.30
runshift Cb15 0.15
runshift Cb25 0.25
echo done > out/lj6/q1d.done
