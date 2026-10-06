#!/bin/sh
# L7 runner handover scan, part 2: the g2 interpolation F1 -> D (D's g3 kept); 384 seeds 65001-65384, controller l7a, j_nat 1 + j_st_w 0.75
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
while [ ! -f out/lj7/ss_r2_bk10_384.done ]; do sleep 2; done
S=65001-65384
B="j_nat=1,j_st_w=0.75"
C=bin/challengers/long_jump_run_y-l7a
rm -f out/lj7/q_run3.done
scratchpad/lj7/ss.sh r2_a05_384 $S "$B" 6 out/lj7/runner_h_0_05_1.txt $C
scratchpad/lj7/ss.sh r2_a075_384 $S "$B" 6 out/lj7/runner_h_0_075_1.txt $C
scratchpad/lj7/ss.sh r2_a025_384 $S "$B" 6 out/lj7/runner_h_0_025_1.txt $C
echo done > out/lj7/q_run3.done
