#!/bin/sh
# L7: TEST (63001-63480) once for the final candidate l7a and once for K3, then EXTRA (67001-67960) once for each (paired baseline). LABELLED beyond-human body, unlimited run-up.
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
rm -f out/lj7/q_final.done
L7=scratchpad/lj7/params/long_jump_beyond_l7a.txt
K3=scratchpad/lj6/params/long_jump_beyond_bo6a.txt
scratchpad/lj7/ev7.sh l7a long_jump_v4_beyond_robust96 $L7 bin/challengers/long_jump_run_y-l7a 63001-63480 6
scratchpad/lj7/ev7.sh K3 long_jump_v4_beyond_robust96 $K3 bin/challengers/long_jump_run_y-l6a 63001-63480 6
scratchpad/lj7/ev7.sh l7a long_jump_v4_beyond_robust96 $L7 bin/challengers/long_jump_run_y-l7a 67001-67960 6
scratchpad/lj7/ev7.sh K3 long_jump_v4_beyond_robust96 $K3 bin/challengers/long_jump_run_y-l6a 67001-67960 6
echo done > out/lj7/q_final.done
