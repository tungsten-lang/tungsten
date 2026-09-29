#!/bin/sh
# Round 10 RSM stage 4 (backhand): the backhand-specific dynamics not yet screened (own co-contraction, postural tone, slide fly-by, swing shift, later contact plane, lateral trim) and
# refreshers of the kick / gain / servo values around c3 (r10-o), on a fresh block bh[500:600], 24 runs. Waits for the arena run.
cd /Users/erik/tungsten/bits/tungsten-robolab

.venv-myo/bin/python playground/tt_rsm.py design --params params/myo_tt_p2_r10_c3.txt --controller bin/challengers/myo_tt_r10-o --pool bh --n 100 --offset 500 --workers 3 --runs 24 --seed 61 \
  --set "" --out out/tt_r10/rsm_bh6 \
  --factors "bh_stiff:0.09:0.13,bh_ki:0:30,bh_pel_fly:0:0.6,bh_dt_swing:0:0.05,bh_dx_hi:0:0.1,lc24:-0.02:0.02,kk2_amp:0.8:1.2,kk_m2:-0.75:-0.55,bh_t_servo:0.28:0.32,bh_gain:0.91:0.94,bh_p_n:0.2:0.4,bh_dnz:-0.05:0.0,k_vpm2:0.4:0.7,ns_k2:0.02:0.08" > out/tt_r10/rsm_bh6.log 2>&1
