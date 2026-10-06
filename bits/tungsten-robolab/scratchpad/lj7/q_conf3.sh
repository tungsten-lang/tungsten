#!/bin/sh
# L7: CONFIRMATION (62001-62480) of K4w75n15 (the retrained landing L1 with the final steering at shift 0.15), after the final candidate's CONFIRMATION
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
while [ ! -f out/lj7/q_conf2.done ]; do sleep 3; done
rm -f out/lj7/q_conf3.done
scratchpad/lj7/ev7.sh K4w75n15 long_jump_v4_beyond_robust96 out/lj6/par_K4.txt bin/challengers/long_jump_run_y-l7a 62001-62480 6 --set j_nat=1,j_st_w=0.75,j_board_shift=0.15,ik_gap0=2.711114225899115
echo done > out/lj7/q_conf3.done
