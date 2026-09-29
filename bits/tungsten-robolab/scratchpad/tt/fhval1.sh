#!/bin/sh
# Forehand validation on 200 independent pool serves (fh_val200 = pool fh[100:300]): champion, bk only, RSM step candidates and the best design runs. 3 workers, sequential.
cd /Users/erik/tungsten/bits/tungsten-robolab
N=bin/challengers/myo_tt_r10-n; CH=bin/champions/tt_p2_300-20260927-194659; P=params/myo_tt_p2_r5_bhprac.txt
scratchpad/tt/ev1.sh val_fh_champ $P $CH scratchpad/tt/fh_val200.txt "" 3
scratchpad/tt/ev1.sh val_fh_bk $P $N scratchpad/tt/fh_val200.txt "bk=1,lc=1,lt_arms=0" 3
scratchpad/tt/ev1.sh val_fh_step1 params/myo_tt_p2_r10_fh_step1.txt $N scratchpad/tt/fh_val200.txt "" 3
scratchpad/tt/ev1.sh val_fh_step05 params/myo_tt_p2_r10_fh_step05.txt $N scratchpad/tt/fh_val200.txt "" 3
scratchpad/tt/ev1.sh val_fh_run16 params/myo_tt_p2_r10_fh_run16.txt $N scratchpad/tt/fh_val200.txt "" 3
scratchpad/tt/ev1.sh val_fh_run1 params/myo_tt_p2_r10_fh_run1.txt $N scratchpad/tt/fh_val200.txt "" 3
