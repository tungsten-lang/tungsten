#!/bin/sh
# Round 10 RSM, forehand pool on the bounce-guard regime (r10-k); starts when the backhand RSM (rsm_run3.sh) has finished.
cd /Users/erik/tungsten/bits/tungsten-robolab
while pgrep -f "[r]sm_run3.sh" > /dev/null; do sleep 10; done
H=bin/challengers/myo_tt_r10-k
P=params/myo_tt_p2_r5_bhprac.txt
S="bk=1,kk=1,kk_amp=0,kk_m1=0.27,kk_m2=-0.48,lc=1,lt_arms=0"
.venv-myo/bin/python playground/tt_rsm.py design --params $P --controller $H --pool fh --n 100 --workers 3 --runs 32 --seed 22 \
  --set "$S" --out out/tt_r10/rsm_fh3 \
  --factors "kk_amp:0.0:1.0,kk_k:0.3:0.7,kk_v0:4.4:5.2,kk_m1:0.05:0.45,t_servo:0.25:0.32,lc0:-0.03:0.03,k_z:8.5:14,k_n:3.5:6.0,p_z:0.0:0.5,p_n:0.15:0.5,nz_bias:-0.15:-0.08,box_x0:-1.3:-1.1,box_x1:-0.8:-0.6,t_lock:0.02:0.04,hx_pad:0.0:0.5,ns_k:-0.05:0.05,k_vpm:0.0:0.5" > out/tt_r10/rsm_fh3.log 2>&1
