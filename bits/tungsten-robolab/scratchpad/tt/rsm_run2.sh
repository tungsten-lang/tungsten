#!/bin/sh
# Round 10 RSM on the bounce-guard regime (r10-k: bk 1): backhand pool, then forehand pool.
# 16 factors per side, 32 random +-1 runs + baseline, 100 fixed serves each (common random numbers).
cd /Users/erik/tungsten/bits/tungsten-robolab
while ! grep -q '^frozen' out/tt_r10/build_v11k.log 2>/dev/null; do sleep 5; done
while [ ! -f scratchpad/tt/qd.stop ]; do sleep 5; done
while pgrep -f "playground/tt_eval.py" > /dev/null; do sleep 5; done
H=bin/challengers/myo_tt_r10-k
P=params/myo_tt_p2_r5_bhprac.txt
S="bk=1,kk=1,kk_amp=0,kk_m1=0.27,kk_m2=-0.48,lc=1,lt_arms=0"
.venv-myo/bin/python playground/tt_rsm.py design --params $P --controller $H --pool bh --n 100 --workers 2 --runs 32 --seed 11 \
  --set "$S" --out out/tt_r10/rsm_bh2 \
  --factors "kk_amp:0.0:1.0,kk_k:0.3:0.7,kk_v0:4.4:5.2,kk_m2:-0.65:-0.3,bh_t_servo:0.20:0.34,lc16:-0.03:0.03,bh_k_z:1.2:6.0,bh_k_n:2.0:7.0,bh_p_z:0.0:0.8,bh_p_n:0.0:0.4,bh_dnz:-0.05:0.15,box_x0:-1.3:-1.05,box_x1:-0.8:-0.55,bh_gain:0.85:1.15,bh_dur:0.40:0.49,ns_k:-0.08:0.08,k_vpm:0.0:0.8" > out/tt_r10/rsm_bh2.log 2>&1
.venv-myo/bin/python playground/tt_rsm.py design --params $P --controller $H --pool fh --n 100 --workers 2 --runs 32 --seed 12 \
  --set "$S" --out out/tt_r10/rsm_fh2 \
  --factors "kk_amp:0.0:1.0,kk_k:0.3:0.7,kk_v0:4.4:5.2,kk_m1:0.05:0.45,t_servo:0.20:0.36,lc0:-0.03:0.03,k_z:7:20,k_n:2.5:8,p_z:0.0:1.0,p_n:0.1:0.6,nz_bias:-0.15:-0.05,box_x0:-1.3:-1.05,box_x1:-0.8:-0.55,t_lock:0.015:0.05,hx_pad:0.0:0.6,ns_k:-0.08:0.08,k_vpm:0.0:0.8" > out/tt_r10/rsm_fh2.log 2>&1
