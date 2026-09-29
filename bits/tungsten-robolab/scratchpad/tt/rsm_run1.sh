#!/bin/sh
# RSM screening on the fixed first 100 backhand-pool serves, then the forehand pool (r10-h: kk, lc)
cd /Users/erik/tungsten/bits/tungsten-robolab
while pgrep -f "playground/tt_eval.py" > /dev/null || pgrep -f "scratchpad/tt/qd.py" > /dev/null || ! grep -q '^built' out/tt_r10/build_v11i.log 2>/dev/null; do sleep 5; done
H=bin/challengers/myo_tt_r10-i
P=params/myo_tt_p2_r5_bhprac.txt
.venv-myo/bin/python playground/tt_rsm.py design --params $P --controller $H --pool bh --n 100 --runs 32 --seed 1 \
  --set "kk=1,kk_amp=0,lc=1,lt_arms=0" --out out/tt_r10/rsm_bh1 \
  --factors "kk_amp:0.0:1.0,kk_k:0.3:0.7,kk_v0:4.4:5.2,kk_m2:-0.5:0.1,bh_t_servo:0.20:0.34,lc16:-0.02:0.05,lc24:-0.03:0.03,bh_k_z:1.2:3.6,bh_k_n:2.0:5.4,bh_dnz:-0.05:0.15,box_x0:-1.35:-1.05,box_x1:-0.9:-0.55,bh_gain:0.75:1.25,bh_dur:0.38:0.50,bh_grip:0.10:0.24,ns_k:-0.08:0.08" > out/tt_r10/rsm_bh1.log 2>&1
.venv-myo/bin/python playground/tt_rsm.py design --params $P --controller $H --pool fh --n 100 --runs 32 --seed 2 \
  --set "kk=1,kk_amp=0,lc=1,lt_arms=0" --out out/tt_r10/rsm_fh1 \
  --factors "kk_amp:0.0:1.0,kk_k:0.3:0.7,kk_v0:4.4:5.2,kk_m1:0.1:0.7,t_servo:0.20:0.35,lc0:-0.02:0.05,lc8:-0.03:0.03,k_z:7:15,k_n:2.5:7,nz_bias:-0.2:-0.05,box_x0:-1.35:-1.05,box_x1:-0.9:-0.55,t_lock:0.015:0.05,hx_pad:0.0:0.6,arm_kp:18:32,ns_k:-0.08:0.08" > out/tt_r10/rsm_fh1.log 2>&1
