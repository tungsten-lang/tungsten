#!/bin/sh
cd /Users/erik/tungsten/bits/tungsten-robolab
C=bin/challengers/myo_tt_r10-b
P=params/myo_tt_p2_r5_bhprac.txt
S=710000:710120
scratchpad/tt/run_variants.sh vb_pv2 $C $P $S "pv=2,lt_arms=0"
scratchpad/tt/run_variants.sh vb_pv2_u0 $C $P $S "pv=2,pv_max=0,lt_arms=0"
