#!/bin/sh
# selB: profile T on the 33 deep-class seeds of the selection set (30 s) and the 40 control seeds (bit-identity against M1)
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
T="rk_thr=-0.05,rk_sr_hip=-0.08,rk_sr_knee=0.5,rk_sr_t0=0.0,rk_sr_dur=0.2,rk_ln_to=0.6,rk_st_hold=0.3"
WORKERS=3 scratchpad/sprint6/scan6.sh selB params/run_geary_v4_beyond_s5b.txt bin/challengers/run_gearz-s6h $(cat out/sprint6/sel_deep.txt) 30 "$T"
WORKERS=3 scratchpad/sprint6/scan6.sh selBn params/run_geary_v4_beyond_s5b.txt bin/challengers/run_gearz-s6h $(cat out/sprint6/sel_nonrisk40.txt) 30 "$T"
