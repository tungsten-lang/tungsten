#!/bin/sh
cd /Users/erik/tungsten/bits/tungsten-robolab
C=bin/champions/tt_p2_300-20260927-194659
P=params/myo_tt_p2_r5_bhprac.txt
S=710000:710120
scratchpad/tt/run_variants.sh v_tlock10 $C $P $S "t_lock=0.10"
scratchpad/tt/run_variants.sh v_nostroke $C $P $S "d_push=0.0,drv_push=0.0"
scratchpad/tt/run_variants.sh v_tlock10_nostroke $C $P $S "t_lock=0.10,d_push=0.0,drv_push=0.0"
