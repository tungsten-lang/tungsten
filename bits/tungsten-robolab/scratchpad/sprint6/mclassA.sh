#!/bin/sh
# mclassA: the marginal class (COM0 in [-0.05, -0.035)) of the FRESH pool (582 seeds of 30001-40000), 6 s: timing levers without / with a gentle step, and the deep-class profile R4
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
SEEDS=$(cat out/sprint6/mclass_fresh.txt)
R4="rk_sr_hip=-0.1,rk_sr_knee=0.5,rk_sr_t0=0.0,rk_sr_dur=0.2,rk_ln_to=0.5,rk_st_hold=0.3"
WORKERS=6 scratchpad/sprint6/scan6.sh mclassA params/run_geary_v4_beyond_s5b.txt bin/challengers/run_gearz-s6h $SEEDS 6 \
  "rk_thr=-0.035" \
  "rk_thr=-0.035,rk_ln_to=0.5" \
  "rk_thr=-0.035,rk_st_hold=0.3" \
  "rk_thr=-0.035,rk_ln_to=0.5,rk_st_hold=0.3" \
  "rk_thr=-0.035,$R4" \
  "rk_thr=-0.035,rk_sr_hip=-0.04,rk_sr_knee=0.25,rk_sr_t0=0.0,rk_sr_dur=0.15,rk_ln_to=0.5,rk_st_hold=0.3"
