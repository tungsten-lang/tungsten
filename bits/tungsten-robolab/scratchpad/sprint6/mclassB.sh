#!/bin/sh
# mclassB: the gentle step of mclassA's best variant on the DEVELOPMENT marginal pool (565 seeds, COM0 in [-0.05, -0.035)), 6 s, with neighbours
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
until grep -q "Done scan classA" out/sprint6/scan_classA.log 2>/dev/null; do sleep 5; done
SEEDS=$(cat out/sprint6/mclass.txt)
B="rk_thr=-0.035,rk_sr_t0=0.0,rk_st_hold=0.3"
WORKERS=6 scratchpad/sprint6/scan6.sh mclassB params/run_geary_v4_beyond_s5b.txt bin/challengers/run_gearz-s6h $SEEDS 6 \
  "rk_thr=-0.035" \
  "$B,rk_sr_hip=-0.04,rk_sr_knee=0.25,rk_sr_dur=0.15,rk_ln_to=0.5" \
  "$B,rk_sr_hip=-0.04,rk_sr_knee=0.25,rk_sr_dur=0.15,rk_ln_to=0.6" \
  "$B,rk_sr_hip=-0.04,rk_sr_knee=0.25,rk_sr_dur=0.15,rk_ln_to=0.7" \
  "$B,rk_sr_hip=-0.05,rk_sr_knee=0.3,rk_sr_dur=0.15,rk_ln_to=0.5" \
  "$B,rk_sr_hip=-0.03,rk_sr_knee=0.2,rk_sr_dur=0.15,rk_ln_to=0.5"
