#!/bin/sh
# deepE: combinations on BOTH deep pools (291 development seeds + 318 fresh seeds = 609), 6 s
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
SEEDS=$(cat out/sprint6/deep_train.txt),$(cat out/sprint6/deep_valid.txt),$(cat out/sprint6/deep_fresh.txt)
B="rk_thr=-0.05,rk_sr_t0=0.0,rk_sr_dur=0.2,rk_sr_knee=0.5"
WORKERS=6 scratchpad/sprint6/scan6.sh deepE params/run_geary_v4_beyond_s5b.txt bin/challengers/run_gearz-s6h $SEEDS 6 \
  "$B,rk_sr_hip=-0.08,rk_ln_to=0.5" \
  "$B,rk_sr_hip=-0.08,rk_ln_to=0.8,rk_st_hold=0.3" \
  "$B,rk_sr_hip=-0.08,rk_ln_to=0.5,rk_st_hold=0.3" \
  "$B,rk_sr_hip=-0.1,rk_ln_to=0.5,rk_st_hold=0.3" \
  "$B,rk_sr_hip=-0.08,rk_ln_to=0.6" \
  "$B,rk_sr_hip=-0.08,rk_ln_to=0.6,rk_st_hold=0.3" \
  "$B,rk_sr_hip=-0.09,rk_ln_to=0.5"
