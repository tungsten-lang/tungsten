#!/bin/sh
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
SEEDS=$(cat out/sprint6/ar_train.txt)
WORKERS=5 scratchpad/sprint6/scan6.sh stepB params/run_geary_v4_beyond_s5b.txt bin/challengers/run_gearz-s6g $SEEDS 6 \
  "rk_thr=-0.035,rk_sr_hip=-0.1,rk_sr_knee=0.5,rk_sr_t0=0.05,rk_sr_dur=0.25,rk_ln_to=0.8" \
  "rk_thr=-0.035,rk_sr_hip=-0.1,rk_sr_knee=0.5,rk_sr_t0=0.05,rk_sr_dur=0.3" \
  "rk_thr=-0.035,rk_sr_hip=-0.15,rk_sr_knee=0.5,rk_sr_t0=0.05,rk_sr_dur=0.2,rk_ln_to=0.8"
