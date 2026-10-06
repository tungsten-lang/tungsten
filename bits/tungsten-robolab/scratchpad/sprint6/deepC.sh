#!/bin/sh
# deepC: combined profile scan on the whole deep pool (291 seeds, 6 s)
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
SEEDS=$(cat out/sprint6/deep_train.txt),$(cat out/sprint6/deep_valid.txt)
B="rk_thr=-0.05,rk_sr_t0=0.0"
WORKERS=6 scratchpad/sprint6/scan6.sh deepC params/run_geary_v4_beyond_s5b.txt bin/challengers/run_gearz-s6h $SEEDS 6 \
  "$B,rk_sr_hip=-0.08,rk_sr_knee=0.4,rk_sr_dur=0.2,rk_ln_to=0.5,rk_st_hold=0.3,rk_psi0=0.65" \
  "$B,rk_sr_hip=-0.08,rk_sr_knee=0.4,rk_sr_dur=0.2,rk_ln_to=0.4,rk_st_hold=0.3,rk_psi0=0.65" \
  "$B,rk_sr_hip=-0.08,rk_sr_knee=0.4,rk_sr_dur=0.2,rk_ln_to=0.3,rk_st_hold=0.3,rk_psi0=0.65" \
  "$B,rk_sr_hip=-0.08,rk_sr_knee=0.4,rk_sr_dur=0.2,rk_ln_to=0.5,rk_st_hold=0.3,rk_psi0=0.75" \
  "$B,rk_sr_hip=-0.06,rk_sr_knee=0.4,rk_sr_dur=0.2,rk_ln_to=0.5,rk_st_hold=0.3,rk_psi0=0.65" \
  "$B,rk_sr_hip=-0.08,rk_sr_knee=0.4,rk_sr_dur=0.15,rk_ln_to=0.5,rk_st_hold=0.3,rk_psi0=0.65" \
  "$B,rk_sr_hip=-0.08,rk_sr_knee=0.3,rk_sr_dur=0.2,rk_ln_to=0.5,rk_st_hold=0.3,rk_psi0=0.65" \
  "$B,rk_sr_hip=-0.08,rk_sr_knee=0.4,rk_sr_dur=0.2,rk_ln_to=0.5,rk_st_hold=0.25,rk_psi0=0.65" \
  "$B,rk_sr_hip=-0.08,rk_sr_knee=0.4,rk_sr_dur=0.2,rk_ln_to=0.6,rk_st_hold=0.3,rk_psi0=0.65" \
  "$B,rk_sr_hip=-0.08,rk_sr_knee=0.4,rk_sr_dur=0.2,rk_ln_to=0.5,rk_st_hold=0.3,rk_psi0=0.65,rk_sr_ankle=-0.05" \
  "$B,rk_sr_hip=-0.07,rk_sr_knee=0.4,rk_sr_dur=0.25,rk_ln_to=0.5,rk_st_hold=0.3,rk_psi0=0.65" \
  "$B,rk_sr_hip=-0.09,rk_sr_knee=0.4,rk_sr_dur=0.2,rk_ln_to=0.5,rk_st_hold=0.3,rk_psi0=0.65"
