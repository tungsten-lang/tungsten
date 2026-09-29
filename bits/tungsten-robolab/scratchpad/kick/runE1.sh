#!/bin/sh
# E1: the follow-through, landing and recovery (parameters read only after the touch), from the touch checkpoints of the noisy P1 dumps whose contact was good.
cd /Users/erik/tungsten/bits/tungsten-robolab
exec .venv-myo/bin/python scratchpad/kick/ksearch.py --init playground/arena/params/soccer_p1-20260926-151503.txt \
  --controller bin/champions/soccer_p1-20260926-151503 --kind touch --good \
  --glob 'p1base_n0.05_*' --glob 'p1base_n0.1_*' --seeds 5000:5048 \
  --only t_follow,th_fol,knee_fol,drv_brake,drv_post,th_land,knee_land,ankle_land,rec_ldx,rec_rdx,rec_dz,fe_rec,t_rec,knee_rec,x_rec \
  --out scratchpad/kick/out/E1.txt --gens 24 --pop 12 --sigma 0.15 --seed 1 --note "E1 recovery from touch checkpoints, noisy P1 dumps 0.05/0.1 seeds 5000-5047"
