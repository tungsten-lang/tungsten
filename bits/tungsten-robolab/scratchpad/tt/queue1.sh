#!/bin/sh
cd /Users/erik/tungsten/bits/tungsten-robolab
# wait for batch2 (script pid 47153) and the v11c build
while kill -0 47153 2>/dev/null; do sleep 5; done
while ! grep -q '^built' out/tt_r10/build_v11c.log 2>/dev/null; do sleep 5; done
C=bin/challengers/myo_tt_r10-c
P=params/myo_tt_p2_r5_bhprac.txt
S=710000:710120
scratchpad/tt/run_variants.sh vc_pv2 $C $P $S "pv=2,lt_arms=0"
scratchpad/tt/batch3.sh
scratchpad/tt/run_variants.sh v_zb03_600 bin/champions/tt_p2_300-20260927-194659 $P 710000:710600 "z_bias=-0.03"
