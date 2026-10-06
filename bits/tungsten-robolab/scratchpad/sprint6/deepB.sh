#!/bin/sh
# deepB: coordinate scan of the rear-step profile around S1b (hip -0.1, knee 0.5, t0 0, dur 0.2, ln_to 0.8) on the whole deep pool (291 seeds, 6 s)
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
SEEDS=$(cat out/sprint6/deep_train.txt),$(cat out/sprint6/deep_valid.txt)
B="rk_thr=-0.05,rk_sr_t0=0.0"
WORKERS=6 scratchpad/sprint6/scan6.sh deepB params/run_geary_v4_beyond_s5b.txt bin/challengers/run_gearz-s6h $SEEDS 6 \
  "$B,rk_sr_hip=-0.1,rk_sr_knee=0.5,rk_sr_dur=0.15,rk_ln_to=0.8" \
  "$B,rk_sr_hip=-0.1,rk_sr_knee=0.5,rk_sr_dur=0.1,rk_ln_to=0.8" \
  "$B,rk_sr_hip=-0.08,rk_sr_knee=0.5,rk_sr_dur=0.2,rk_ln_to=0.8" \
  "$B,rk_sr_hip=-0.12,rk_sr_knee=0.5,rk_sr_dur=0.2,rk_ln_to=0.8" \
  "$B,rk_sr_hip=-0.15,rk_sr_knee=0.5,rk_sr_dur=0.2,rk_ln_to=0.8" \
  "$B,rk_sr_hip=-0.1,rk_sr_knee=0.3,rk_sr_dur=0.2,rk_ln_to=0.8" \
  "$B,rk_sr_hip=-0.1,rk_sr_knee=0.7,rk_sr_dur=0.2,rk_ln_to=0.8" \
  "$B,rk_sr_hip=-0.1,rk_sr_knee=0.9,rk_sr_dur=0.2,rk_ln_to=0.8" \
  "$B,rk_sr_hip=-0.1,rk_sr_knee=0.5,rk_sr_dur=0.2,rk_ln_to=0.5" \
  "$B,rk_sr_hip=-0.1,rk_sr_knee=0.5,rk_sr_dur=0.2,rk_ln_to=1.2" \
  "$B,rk_sr_hip=-0.1,rk_sr_knee=0.5,rk_sr_dur=0.2,rk_ln_to=0.8,rk_sr_ankle=0.1" \
  "$B,rk_sr_hip=-0.1,rk_sr_knee=0.5,rk_sr_dur=0.2,rk_ln_to=0.8,rk_sr_ankle=-0.1" \
  "$B,rk_sr_hip=-0.1,rk_sr_knee=0.5,rk_sr_dur=0.2,rk_ln_to=0.8,rk_st_hold=0.3" \
  "$B,rk_sr_hip=-0.1,rk_sr_knee=0.5,rk_sr_dur=0.2,rk_ln_to=0.8,rk_psi0=0.45" \
  "$B,rk_sr_hip=-0.1,rk_sr_knee=0.5,rk_sr_dur=0.2,rk_ln_to=0.8,rk_psi0=0.65"
