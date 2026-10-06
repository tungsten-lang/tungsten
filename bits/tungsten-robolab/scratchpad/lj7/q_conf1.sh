#!/bin/sh
# L7: CONFIRMATION (62001-62480) of K3 + j_nat 1 at the joint shift 0.15 (controller l7a) and of K3 (controller l6a), the paired baseline
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
while [ ! -f out/lj7/q_run1.done ]; do sleep 3; done
rm -f out/lj7/q_conf1.done
K3=scratchpad/lj6/params/long_jump_beyond_bo6a.txt
scratchpad/lj7/ev7.sh K3n15 long_jump_v4_beyond_robust96 $K3 bin/challengers/long_jump_run_y-l7a 62001-62480 6 --set j_nat=1,j_board_shift=0.15,ik_gap0=2.711114225899115
scratchpad/lj7/ev7.sh K3 long_jump_v4_beyond_robust96 $K3 bin/challengers/long_jump_run_y-l6a 62001-62480 6
echo done > out/lj7/q_conf1.done
