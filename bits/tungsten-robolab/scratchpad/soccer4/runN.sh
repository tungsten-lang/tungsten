#!/bin/sh
cd /Users/erik/tungsten/bits/tungsten-robolab
exec .venv-myo/bin/python scratchpad/soccer4/search4.py --init scratchpad/soccer4/ks5_init.txt \
  --out scratchpad/soccer4/sN.txt --stage kick2 \
  --controller scratchpad/soccer4/ctl_v7a --seed_list 8545,8356,7914,7882,8331,7908,8087,7449,7453,8304,7505,7786,8391,8239,7885,8393,7469,8262,8502,7777,7562,8373,8552,7621,8224,8259,8242,8091,7750,7824,7992,7972,8481,7823,7411,7597,8564,8140,8355,7440 \
  --k 8 --gens 30 --pop 14 --workers 4 --seconds 10 --sigma 0.15 \
  --note "N: the kick from a settled stance (ks5: the routine's settle, then the run-up and kick) on P2 starts within 0.3 m of the P1 start" \
  --only b_t_set,bs_v,bs_tmax,t_shift,shift_x,shift_y,unload,shift_add,d_go,x_step,t_lift,lift_dx,lift_dz,lift_h,reach_dx,reach_dz,reach_pitch,k_ik,k_py,reach_lat,tilt_step,t_reach,add_reach,push_dx,push_dz,drv_push,min_step,plant_load,plant_dx,plant_dy,k_ax_st,x_plant,t_swing,hip_snap,th_k1,knee_k1,t_snap,th_k2,knee_k2,ankle_k,drv_hip,drv_knee,g_kick,g_anta,g_st,drv_st,k_ky,kick_dy,ks_dx,ks_dz,add_pl,fe_step
