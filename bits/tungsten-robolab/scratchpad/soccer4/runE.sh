#!/bin/sh
cd /Users/erik/tungsten/bits/tungsten-robolab
exec .venv-myo/bin/python scratchpad/soccer4/search4.py --init scratchpad/soccer4/rk_init.txt \
  --out scratchpad/soccer4/sE.txt --stage inside --env myoChallengeSoccerP1-v0 \
  --controller scratchpad/soccer4/ctl_v4e --seed0 700 --k 4 --gens 20 --pop 12 --workers 3 --seconds 5 --sigma 0.15 \
  --note "E: side-foot running kick + rk4 (tlh on the run-up and plant, plant foot turned in the air)" \
  --only rk_head,rk_plant,rk_kick,tl_kp,tl_kd,tl_cap,fy_k,fy_lim,s_rot,s_open,s_ankle,s_knee1,s_knee2,s_add,s_dy,s_th_cock,s_knee_cock,s_drv_add,s_drv_ank,s_drv_knee,th_k1,th_k2,hip_snap,drv_hip,plant_dx,plant_dy,k_ky,s_aim_dy
