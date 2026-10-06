#!/bin/sh
# Q4 (SELECTION 31001-31480; LABELLED beyond-human body, unlimited run-up): the runner frontier beyond chain D: linear extrapolation alpha 1.25 / 1.5 of the F1 -> D parameter differences, C7's tables.
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
while [ ! -f out/lj6/q3.done ]; do sleep 5; done
rm -f out/lj6/q4.done
T=long_jump_v4_beyond_robust96
S=31001-31480
L4B=bin/challengers/long_jump_run_y-l4b
scratchpad/lj6/ev6.sh Ra125 $T out/lj6/par_Ra1.25.txt $L4B $S 6
scratchpad/lj6/ev6.sh Ra150 $T out/lj6/par_Ra1.5.txt $L4B $S 6
echo done > out/lj6/q4.done
