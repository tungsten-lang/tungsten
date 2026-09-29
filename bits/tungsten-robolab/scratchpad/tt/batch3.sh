#!/bin/sh
# anticipation and consolidation tests on the champion binary (params only)
cd /Users/erik/tungsten/bits/tungsten-robolab
C=bin/champions/tt_p2_300-20260927-194659
P=params/myo_tt_p2_r5_bhprac.txt
S=710000:710120
scratchpad/tt/run_variants.sh v_ffz $C $P $S "g_ffz=1.0,ff_z=1.32,ff_nx=0.91,ff_ny=0.21,ff_nz=-0.36"
scratchpad/tt/run_variants.sh v_ffzn $C $P $S "g_ffz=1.0,g_ffn=1.0,ff_z=1.32,ff_nx=0.91,ff_ny=0.21,ff_nz=-0.36"
scratchpad/tt/run_variants.sh v_consol $C $P $S "sh_elv=0.104,elbow=1.075,pro_sup=1.124,wflex=-0.651,dev=-0.128,elv=0.345"
scratchpad/tt/run_variants.sh v_tservo20 $C $P $S "t_servo=0.20"
