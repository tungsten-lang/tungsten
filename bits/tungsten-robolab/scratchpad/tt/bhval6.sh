#!/bin/sh
# Backhand stage-5 candidates (rsm_bh7) and c5 on 200 backhand serves nobody has used (pool 750000: bh750[0:200]). r10-n, 3 workers.
cd /Users/erik/tungsten/bits/tungsten-robolab
N=bin/challengers/myo_tt_r10-n
scratchpad/tt/ev1.sh f2_bh_c5 params/myo_tt_p2_r10_c5.txt $N scratchpad/tt/bh750_a.txt "" 3
for c in step1 step05 run1 run5; do
  scratchpad/tt/ev1.sh f2_bh_s5_$c params/myo_tt_p2_r10_bh7_$c.txt $N scratchpad/tt/bh750_a.txt "" 3
done
scratchpad/tt/ev1.sh f2_bh_champ params/myo_tt_p2_r5_bhprac.txt bin/champions/tt_p2_300-20260927-194659 scratchpad/tt/bh750_a.txt "" 3
scratchpad/tt/ev1.sh f2_bh_c3 params/myo_tt_p2_r10_c3.txt $N scratchpad/tt/bh750_a.txt "" 3
