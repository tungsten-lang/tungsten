#!/bin/sh
# L7 runner handover scan (the mid-run falls are GEAR-2 forward pitch falls 2-3 s after the 1->2 switch): g2 interpolation F1 -> D and the S5 blending / gating keys; 384 seeds 65001-65384, controller l7a, j_nat 1 + j_st_w 0.75
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
S=65001-65384
rm -f out/lj7/q_run2.done
B="j_nat=1,j_st_w=0.75"
H=scratchpad/lj6/params/runner_H011_SB2.txt
C=bin/challengers/long_jump_run_y-l7a
scratchpad/lj7/ss.sh r2_bk05_384 $S "$B,g2_t_blendk=0.5" 6 $H $C
scratchpad/lj7/ss.sh r2_bk10_384 $S "$B,g2_t_blendk=1.0" 6 $H $C
scratchpad/lj7/ss.sh r2_b05_384 $S "$B,g2_t_blend=0.5" 6 $H $C
scratchpad/lj7/ss.sh r2_a05_384 $S "$B" 6 out/lj7/runner_h_0_05_1.txt $C
scratchpad/lj7/ss.sh r2_a075_384 $S "$B" 6 out/lj7/runner_h_0_075_1.txt $C
scratchpad/lj7/ss.sh r2_a025_384 $S "$B" 6 out/lj7/runner_h_0_025_1.txt $C
scratchpad/lj7/ss.sh r2_swr07_384 $S "$B,sw_r=0.7" 6 $H $C
echo done > out/lj7/q_run2.done
