#!/bin/sh
# Fresh backhand serves bh[600:796] (196, never used): c3, the stage-4 consensus c4, runs 18 and 7. r10-o (same shared options as r10-n), 3 workers.
cd /Users/erik/tungsten/bits/tungsten-robolab
O=bin/challengers/myo_tt_r10-o
scratchpad/tt/ev1.sh fr_bh_c3 params/myo_tt_p2_r10_c3.txt $O scratchpad/tt/bh_fresh196.txt "" 3
scratchpad/tt/ev1.sh fr_bh_c4 params/myo_tt_p2_r10_c4.txt $O scratchpad/tt/bh_fresh196.txt "" 3
scratchpad/tt/ev1.sh fr_bh_run18 params/myo_tt_p2_r10_bh6_run18.txt $O scratchpad/tt/bh_fresh196.txt "" 3
scratchpad/tt/ev1.sh fr_bh_run7 params/myo_tt_p2_r10_bh6_run7.txt $O scratchpad/tt/bh_fresh196.txt "" 3
scratchpad/tt/ev1.sh fr_bh_champ params/myo_tt_p2_r5_bhprac.txt bin/champions/tt_p2_300-20260927-194659 scratchpad/tt/bh_fresh196.txt "" 3
