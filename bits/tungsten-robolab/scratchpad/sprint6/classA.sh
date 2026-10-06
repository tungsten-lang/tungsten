#!/bin/sh
# classA: one profile for the whole at-risk class COM0 < -0.035: fresh deep pool (318) + fresh marginal pool (582), 6 s; timing levers ln_to 0.6, hold 0.3, t0 0
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
SEEDS=$(cat out/sprint6/deep_fresh.txt),$(cat out/sprint6/mclass_fresh.txt)
B="rk_thr=-0.035,rk_sr_t0=0.0,rk_ln_to=0.6,rk_st_hold=0.3"
WORKERS=6 scratchpad/sprint6/scan6.sh classA params/run_geary_v4_beyond_s5b.txt bin/challengers/run_gearz-s6h $SEEDS 6 \
  "rk_thr=-0.035" \
  "$B,rk_sr_hip=-0.04,rk_sr_knee=0.25,rk_sr_dur=0.15" \
  "$B,rk_sr_hip=-0.06,rk_sr_knee=0.35,rk_sr_dur=0.2" \
  "$B,rk_sr_hip=-0.08,rk_sr_knee=0.5,rk_sr_dur=0.2" \
  "$B,rk_sr_hip=-0.06,rk_sr_knee=0.5,rk_sr_dur=0.2" \
  "$B,rk_sr_hip=-0.05,rk_sr_knee=0.3,rk_sr_dur=0.15" \
  "$B,rk_sr_hip=-0.03,rk_sr_knee=0.2,rk_sr_dur=0.15" \
  "$B,rk_sr_hip=-0.04,rk_sr_knee=0.25,rk_sr_dur=0.2" \
  "$B,rk_sr_hip=-0.05,rk_sr_knee=0.4,rk_sr_dur=0.2"
