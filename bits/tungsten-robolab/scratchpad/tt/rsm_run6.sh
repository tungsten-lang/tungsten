#!/bin/sh
# Round 10 RSM stage 2 (backhand): narrow ranges around RSM run 21 (params/myo_tt_p2_r10_c0.txt, r10-n), on a FRESH block of backhand-pool serves (bh[400:500]).
cd /Users/erik/tungsten/bits/tungsten-robolab
while pgrep -f "[r]sm_run5.sh" > /dev/null; do sleep 10; done
while ! grep -q '^frozen' out/tt_r10/build_v11n.log 2>/dev/null; do sleep 10; done
H=bin/challengers/myo_tt_r10-n
P=params/myo_tt_p2_r10_c0.txt
.venv-myo/bin/python playground/tt_rsm.py design --params $P --controller $H --pool bh --n 100 --offset 400 --workers 3 --runs 28 --seed 31 \
  --set "" --out out/tt_r10/rsm_bh4 \
  --factors "bh_gain:0.90:0.95,kk2_amp:0.6:1.2,kk2_k:0.15:0.5,kk2_v0:4.9:5.5,kk_m2:-0.85:-0.45,bh_t_servo:0.27:0.33,lc16:-0.05:0.0,bh_k_z:1.2:2.2,bh_k_n:2.4:3.6,bh_p_z:0.0:0.25,bh_p_n:0.2:0.5,bh_dnz:-0.06:0.02,bh_dur:0.44:0.49,ns_k2:0.0:0.09,k_vpm2:0.3:0.8" > out/tt_r10/rsm_bh4.log 2>&1
