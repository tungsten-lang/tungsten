#!/bin/sh
# Q6 (SELECTION): hybrid runners with C7's tables (controller l4b): H001 = F1 start + F1 handover + chain D's top gear; H011 = F1 start + chain D's gears 2 and 3; H101 = chain D start + F1 handover + chain D top gear.
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
while [ ! -f out/lj6/q5.done ]; do sleep 5; done
rm -f out/lj6/q6.done
T=long_jump_v4_beyond_robust96
S=31001-31480
L4B=bin/challengers/long_jump_run_y-l4b
scratchpad/lj6/ev6.sh H001 $T out/lj6/par_H001.txt $L4B $S 6
scratchpad/lj6/ev6.sh H011 $T out/lj6/par_H011.txt $L4B $S 6
echo done > out/lj6/q6.done
