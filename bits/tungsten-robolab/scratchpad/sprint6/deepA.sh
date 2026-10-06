#!/bin/sh
# deepA: S1 and variants on ALL 291 deep-class pool seeds (com0 < -0.05), 6 s
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
SEEDS=$(cat out/sprint6/deep_train.txt),$(cat out/sprint6/deep_valid.txt)
WORKERS=6 scratchpad/sprint6/scan6.sh deepA params/run_geary_v4_beyond_s5b.txt bin/challengers/run_gearz-s6h $SEEDS 6 \
  "rk_thr=-0.05" \
  "rk_thr=-0.05,rk_sr_hip=-0.1,rk_sr_knee=0.5,rk_sr_t0=0.05,rk_sr_dur=0.25,rk_ln_to=0.8" \
  "rk_thr=-0.05,rk_sr_hip=-0.1,rk_sr_knee=0.5,rk_sr_t0=0.0,rk_sr_dur=0.2,rk_ln_to=0.8" \
  "rk_thr=-0.05,rk_sr_hip=-0.12,rk_sr_knee=0.6,rk_sr_t0=0.0,rk_sr_dur=0.2,rk_ln_to=0.8,rk_st_ankle=0.0476,rk_psi0=0.5633"
