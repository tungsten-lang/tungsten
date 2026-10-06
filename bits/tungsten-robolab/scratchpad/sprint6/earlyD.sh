#!/bin/sh
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
SEEDS=$(cat out/sprint6/ar_train.txt)
WORKERS=6 scratchpad/sprint6/scan6.sh earlyD params/run_geary_v4_beyond_s5b.txt bin/challengers/run_gearz-s6f $SEEDS 6 \
  "rk_thr=-0.035" \
  "rk_thr=-0.035,rk_cap_st=0.05,rk_rate_st=0.1" \
  "rk_thr=-0.035,rk_cap_st=0.03,rk_rate_st=0.1" \
  "rk_thr=-0.035,rk_cap_st=0.08,rk_rate_st=0.1" \
  "rk_thr=-0.035,rk_cap_st=0.12,rk_rate_st=0.1" \
  "rk_thr=-0.035,rk_cap_st=0.05,rk_rate_st=0.05" \
  "rk_thr=-0.035,rk_cap_st=0.05,rk_rate_st=0.2" \
  "rk_thr=-0.035,rk_cap_st=0.0" \
  "rk_thr=-0.035,rk_rate_st=0.1" \
  "rk_thr=-0.035,rk_cap_st=0.05,rk_rate_st=0.1,rk_cap_ln=0.1,rk_rate_ln=0.2" \
  "rk_thr=-0.035,rk_cap_st=0.05,rk_rate_st=0.1,rk_ln_to=0.8" \
  "rk_thr=-0.035,rk_cap_st=0.05,rk_rate_st=0.1,rk_ln_to=3.0"
