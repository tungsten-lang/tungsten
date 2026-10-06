#!/bin/sh
# Q5 (SELECTION): wait for the running D7s20 evaluation, then the runner extrapolation beyond chain D (alpha 1.25, 1.5; C7's tables; controller l4b).
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
while pgrep -f "scratchpad/lj6/ev6.sh D7s20" > /dev/null; do sleep 3; done
rm -f out/lj6/q5.done
T=long_jump_v4_beyond_robust96
S=31001-31480
L4B=bin/challengers/long_jump_run_y-l4b
scratchpad/lj6/ev6.sh Ra125 $T out/lj6/par_Ra1.25.txt $L4B $S 6
scratchpad/lj6/ev6.sh Ra150 $T out/lj6/par_Ra1.5.txt $L4B $S 6
echo done > out/lj6/q5.done
