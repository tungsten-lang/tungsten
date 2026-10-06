#!/bin/sh
# L7: K3 + j_nat 1 (the toe-off natural-step predictor; controller l7a) on SELECTION 61001-61480 at joint board shifts 0.10 / 0.15 / 0.20 / 0.25 (j_board_shift d, ik_gap0 2.861114225899115 - d)
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
while [ ! -f out/lj7/q_ss2.done ]; do sleep 3; done
rm -f out/lj7/q_sel1.done
K3=scratchpad/lj6/params/long_jump_beyond_bo6a.txt
C=bin/challengers/long_jump_run_y-l7a
scratchpad/lj7/ev7.sh K3n10 long_jump_v4_beyond_robust96 $K3 $C 61001-61480 6 --set j_nat=1
scratchpad/lj7/ev7.sh K3n15 long_jump_v4_beyond_robust96 $K3 $C 61001-61480 6 --set j_nat=1,j_board_shift=0.15,ik_gap0=2.711114225899115
scratchpad/lj7/ev7.sh K3n20 long_jump_v4_beyond_robust96 $K3 $C 61001-61480 6 --set j_nat=1,j_board_shift=0.20,ik_gap0=2.661114225899115
scratchpad/lj7/ev7.sh K3n25 long_jump_v4_beyond_robust96 $K3 $C 61001-61480 6 --set j_nat=1,j_board_shift=0.25,ik_gap0=2.611114225899115
echo done > out/lj7/q_sel1.done
