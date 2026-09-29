#!/bin/sh
# Round 10 RSM stage 5 (backhand): further along stage 4's winning directions around c5 (run 18; params c5, r10-n), fresh block bh[300:400], 24 runs. Waits for the c5 block runs.
cd /Users/erik/tungsten/bits/tungsten-robolab
while pgrep -f "[m]ixval.sh" > /dev/null || pgrep -f "[c]5_block2.sh" > /dev/null; do sleep 10; done
.venv-myo/bin/python playground/tt_rsm.py design --params params/myo_tt_p2_r10_c5.txt --controller bin/challengers/myo_tt_r10-n --pool bh --n 100 --offset 300 --workers 3 --runs 24 --seed 71 \
  --set "" --out out/tt_r10/rsm_bh7 \
  --factors "bh_pel_fly:0.4:1.0,bh_gain:0.89:0.93,bh_stiff:0.11:0.16,kk2_amp:1.0:1.4,kk_m2:-0.65:-0.40,bh_p_n:0.1:0.3,k_vpm2:0.5:0.95,bh_dnz:-0.08:-0.02,lc24:-0.04:0.0,ns_k2:0.0:0.06,bh_t_servo:0.29:0.34,bh_dt_swing:0.0:0.02,bh_dx_hi:0.0:0.05,bh_ki:0:20" > out/tt_r10/rsm_bh7.log 2>&1
