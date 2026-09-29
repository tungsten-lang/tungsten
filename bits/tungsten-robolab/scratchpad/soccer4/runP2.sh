#!/bin/sh
cd /Users/erik/tungsten/bits/tungsten-robolab
exec .venv-myo/bin/python scratchpad/soccer4/search4.py --init scratchpad/soccer4/plant2_init.txt \
  --out scratchpad/soccer4/sP2.txt --stage plant5 \
  --controller scratchpad/soccer4/ctl_v7d --seed_list 8545,8356,7914,7882,8331,7908,8087,7449,7453,8304,7505,7786,8391,8239,7885,8393,7469,8262,8502,7777,7562,8373,8552,7621,8224,8259,8242,8091,7750,7824,7992,7972,8481,7823,7411,7597,8564,8140,8355,7440 \
  --k 8 --gens 30 --pop 14 --workers 4 --seconds 6 --sigma 0.15 \
  --note "P2 (rk4: heading hold and plant foot turned in the air; yaw at the plant shaped): the settled run-up's plant (ks5, direct 0, stage 1): land beside the ball and stand on the plant foot, kicking leg wound back" \
  --only t_shift,shift_x,shift_y,unload,shift_add,d_go,x_step,t_lift,lift_dx,lift_dz,lift_h,reach_dx,reach_dz,reach_pitch,k_ik,k_py,reach_lat,tilt_step,t_reach,add_reach,push_dx,push_dz,drv_push,min_step,plant_load,plant_dx,plant_dy,k_ax_st,x_plant,lg_dx,lg_dz,lg_pitch,lr_dx,lr_dz,lr_pitch,add_pl,t_lunge,t_lunge_max,unload_r,x_lunge,y_lunge,t_plant,th_back,knee_back,ankle_back,ks_dx,ks_dz,fe_step,g_st,drv_st,rk_head,rk_plant,rk_kick,rk_yawc,tl_kp,tl_kd,tl_cap,fy_k,fy_lim
