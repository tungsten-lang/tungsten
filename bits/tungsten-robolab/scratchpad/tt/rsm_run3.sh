#!/bin/sh
# Round 10 RSM, narrower ranges (the wide design's first corner collapsed to 3 % solved): backhand pool on the bounce-guard regime (r10-k).
cd /Users/erik/tungsten/bits/tungsten-robolab
H=bin/challengers/myo_tt_r10-k
P=params/myo_tt_p2_r5_bhprac.txt
S="bk=1,kk=1,kk_amp=0,kk_m1=0.27,kk_m2=-0.48,lc=1,lt_arms=0"
.venv-myo/bin/python playground/tt_rsm.py design --params $P --controller $H --pool bh --n 100 --workers 3 --runs 32 --seed 21 \
  --set "$S" --out out/tt_r10/rsm_bh3 \
  --factors "kk_amp:0.0:1.0,kk_k:0.3:0.7,kk_v0:4.4:5.2,kk_m2:-0.65:-0.30,bh_t_servo:0.24:0.30,lc16:-0.03:0.03,bh_k_z:1.6:3.2,bh_k_n:2.9:4.6,bh_p_z:0.0:0.4,bh_p_n:0.0:0.3,bh_dnz:-0.03:0.08,box_x0:-1.3:-1.1,box_x1:-0.8:-0.6,bh_gain:0.92:1.05,bh_dur:0.42:0.47,ns_k:-0.05:0.05,k_vpm:0.0:0.5" > out/tt_r10/rsm_bh3.log 2>&1
