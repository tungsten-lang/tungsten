#!/bin/sh
# closed-loop height matching and centring tests on the champion binary (params only)
cd /Users/erik/tungsten/bits/tungsten-robolab
C=bin/champions/tt_p2_300-20260927-194659
P=params/myo_tt_p2_r5_bhprac.txt
S=710000:710120
scratchpad/tt/run_variants.sh v_hxpad05 $C $P $S "hx_pad=0.5,z_bias=-0.03"
scratchpad/tt/run_variants.sh v_hxpad10 $C $P $S "hx_pad=1.0,z_bias=0.0"
scratchpad/tt/run_variants.sh v_zb03_120 $C $P $S "z_bias=-0.03"
scratchpad/tt/run_variants.sh v_hxpad10_xhi22 $C $P $S "hx_pad=1.0,z_bias=0.0,x_hi=2.2"
