#!/bin/sh
# Round 10 RSM stage 3 (backhand): posture, slide offset and grip around run 21 (params c2, r10-o), fresh block bh[400:500] (as stage 2), 20 runs. Waits for ysw.sh.
cd /Users/erik/tungsten/bits/tungsten-robolab
while pgrep -f "[y]sw.sh" > /dev/null; do sleep 10; done
.venv-myo/bin/python playground/tt_rsm.py design --params params/myo_tt_p2_r10_c2.txt --controller bin/challengers/myo_tt_r10-o --pool bh --n 100 --offset 400 --workers 3 --runs 20 --seed 41 \
  --set "" --out out/tt_r10/rsm_bh5 \
  --factors "bh_elv:-1.277:-1.177,bh_sh_elv:0.703:0.783,bh_elbow:1.98:2.04,bh_dev:-0.11:-0.04,bh_wflex:0.22:0.27,bh_trunk_ar:0.36:0.48,bh_off:-0.26:-0.20,bh_y_trim:-0.03:0.03,bh_grip:0.13:0.20,bh_dz_hit:-0.03:0.03,bh_dd_push:-0.05:0.03" > out/tt_r10/rsm_bh5.log 2>&1
