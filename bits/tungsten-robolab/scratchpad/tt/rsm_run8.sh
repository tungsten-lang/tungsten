#!/bin/sh
# Round 10 RSM stage B (forehand): the forehand's arm gain (fh_gain, r10-p: the analogue of bh_gain, the backhand's strongest factor), posture, servo and lateral trim around the champion's forehand
# (params c3: the champion's forehand exactly), fresh block fh[400:500], 24 runs. Waits for the backhand stage 4 (rsm_run9.sh) and the r10-p build.
cd /Users/erik/tungsten/bits/tungsten-robolab
while pgrep -f "[r]sm_run9.sh" > /dev/null; do sleep 10; done
while ! grep -q '^frozen' out/tt_r10/build_v11p.log 2>/dev/null; do sleep 10; done
.venv-myo/bin/python playground/tt_rsm.py design --params params/myo_tt_p2_r10_c3.txt --controller bin/challengers/myo_tt_r10-p --pool fh --n 100 --offset 400 --workers 2 --runs 24 --seed 51 \
  --set "" --out out/tt_r10/rsm_fh5 \
  --factors "fh_gain:0.88:1.10,elv:0.31:0.41,sh_elv:0.447:0.527,sh_rot:-1.35:-1.24,elbow:1.18:1.26,pro_sup:1.12:1.28,dev:-0.17:-0.10,wflex:-0.78:-0.72,y_trim:0.0:0.06,lc0:-0.02:0.02,t_servo:0.265:0.29,nz_bias:-0.15:-0.11,k_z:9.5:12.5,k_n:4.0:5.4,hx_sag:0.2:0.4" > out/tt_r10/rsm_fh5.log 2>&1
