#!/bin/sh
# L7: the final steering (j_nat 1, j_st_w 0.75) with K3's tables on SELECTION at joint shifts 0.15 / 0.12 / 0.18, and K4 (the retrained landing L1, out/lj6/par_K4.txt) at 0.15
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
rm -f out/lj7/q_sel2.done
K3=scratchpad/lj6/params/long_jump_beyond_bo6a.txt
K4=out/lj6/par_K4.txt
C=bin/challengers/long_jump_run_y-l7a
scratchpad/lj7/ev7.sh K3w75n15 long_jump_v4_beyond_robust96 $K3 $C 61001-61480 6 --set j_nat=1,j_st_w=0.75,j_board_shift=0.15,ik_gap0=2.711114225899115
scratchpad/lj7/ev7.sh K3w75n12 long_jump_v4_beyond_robust96 $K3 $C 61001-61480 6 --set j_nat=1,j_st_w=0.75,j_board_shift=0.12,ik_gap0=2.741114225899115
scratchpad/lj7/ev7.sh K3w75n18 long_jump_v4_beyond_robust96 $K3 $C 61001-61480 6 --set j_nat=1,j_st_w=0.75,j_board_shift=0.18,ik_gap0=2.681114225899115
scratchpad/lj7/ev7.sh K4w75n15 long_jump_v4_beyond_robust96 $K4 $C 61001-61480 6 --set j_nat=1,j_st_w=0.75,j_board_shift=0.15,ik_gap0=2.711114225899115
echo done > out/lj7/q_sel2.done
