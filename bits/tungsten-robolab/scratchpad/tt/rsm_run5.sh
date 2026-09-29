#!/bin/sh
# Round 10 RSM, forehand pool, narrow ranges around the tuned centre (bk regime, r10-k).
cd /Users/erik/tungsten/bits/tungsten-robolab
H=bin/challengers/myo_tt_r10-k
P=params/myo_tt_p2_r5_bhprac.txt
S="bk=1,kk=1,kk_amp=0,kk_m1=0.27,kk_m2=-0.48,lc=1,lt_arms=0"
.venv-myo/bin/python playground/tt_rsm.py design --params $P --controller $H --pool fh --n 100 --workers 3 --runs 32 --seed 22 \
  --set "$S" --out out/tt_r10/rsm_fh3 \
  --factors "kk_amp:0.0:1.0,kk_k:0.3:0.5,kk_v0:4.8:5.4,kk_m1:0.1:0.4,t_servo:0.26:0.30,lc0:-0.02:0.02,k_z:9:13,k_n:4.0:5.5,p_z:0.0:0.3,p_n:0.2:0.45,nz_bias:-0.15:-0.10,box_x0:-1.25:-1.15,box_x1:-0.75:-0.65,t_lock:0.02:0.035,hx_pad:0.0:0.4,ns_k:-0.04:0.04,k_vpm:0.0:0.4" > out/tt_r10/rsm_fh3.log 2>&1
