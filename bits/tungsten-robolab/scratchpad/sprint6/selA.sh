#!/bin/sh
# selA: candidate S1 (rear step) on the 33 deep-class seeds of the selection set (30 s) and on 40 not-at-risk seeds (bit-identity check against M1)
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
S1="rk_thr=-0.05,rk_sr_hip=-0.1,rk_sr_knee=0.5,rk_sr_t0=0.05,rk_sr_dur=0.25,rk_ln_to=0.8"
WORKERS=5 scratchpad/sprint6/scan6.sh selA params/run_geary_v4_beyond_s5b.txt bin/challengers/run_gearz-s6g $(cat out/sprint6/sel_deep.txt) 30 "$S1"
WORKERS=5 scratchpad/sprint6/scan6.sh selAn params/run_geary_v4_beyond_s5b.txt bin/challengers/run_gearz-s6g $(cat out/sprint6/sel_nonrisk40.txt) 30 "$S1"
