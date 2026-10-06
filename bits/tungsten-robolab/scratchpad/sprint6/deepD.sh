#!/bin/sh
# deepD: candidate step profiles on the FRESH deep pool (318 seeds of 30001-40000 with COM0 < -0.05), 6 s
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
SEEDS=$(cat out/sprint6/deep_fresh.txt)
B="rk_thr=-0.05,rk_sr_t0=0.0"
WORKERS=6 scratchpad/sprint6/scan6.sh deepD params/run_geary_v4_beyond_s5b.txt bin/challengers/run_gearz-s6h $SEEDS 6 \
  "rk_thr=-0.05" \
  "$B,rk_sr_hip=-0.1,rk_sr_knee=0.5,rk_sr_dur=0.2,rk_ln_to=0.8" \
  "$B,rk_sr_hip=-0.1,rk_sr_knee=0.5,rk_sr_dur=0.2,rk_ln_to=0.8,rk_st_hold=0.3" \
  "$B,rk_sr_hip=-0.1,rk_sr_knee=0.5,rk_sr_dur=0.2,rk_ln_to=0.5" \
  "$B,rk_sr_hip=-0.08,rk_sr_knee=0.4,rk_sr_dur=0.2,rk_ln_to=0.6,rk_st_hold=0.3,rk_psi0=0.65" \
  "$B,rk_sr_hip=-0.1,rk_sr_knee=0.5,rk_sr_dur=0.2,rk_ln_to=0.8,rk_psi0=0.65" \
  "$B,rk_sr_hip=-0.08,rk_sr_knee=0.5,rk_sr_dur=0.2,rk_ln_to=0.8" \
  "$B,rk_sr_hip=-0.1,rk_sr_knee=0.5,rk_sr_dur=0.25,rk_ln_to=0.8" \
  "rk_thr=-0.05,rk_sr_hip=-0.1,rk_sr_knee=0.5,rk_sr_t0=0.05,rk_sr_dur=0.25,rk_ln_to=0.8"
