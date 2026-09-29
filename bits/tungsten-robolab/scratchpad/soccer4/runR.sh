#!/bin/sh
cd /Users/erik/tungsten/bits/tungsten-robolab
exec .venv-myo/bin/python scratchpad/soccer4/search4.py --init scratchpad/soccer4/clone_init.txt \
  --out scratchpad/soccer4/sR.txt --stage clone \
  --controller scratchpad/soccer4/ctl_v7f --seed_list 8545,8356,7914,7882,8331,7908,8087,7449,7453,8304,7505,7786,8391,8239,7885,8393,7469,8262,8502,7777,7562,8373,8552,7621,8224,8259,8242,8091,7750,7824,7992,7972,8481,7823,7411,7597,8564,8140,8355,7440 \
  --k 8 --gens 30 --pop 14 --workers 4 --seconds 6 --sigma 0.15 \
  --note "R: the phase-1 champion's plant state cloned from the routine's settled stance (run-up params searched, the champion's swing kept), near P2 starts" \
  --only b_t_set,bs_v,t_shift,shift_x,shift_y,unload,shift_add,shift_st,d_go,x_step,k_st2,k_ax_st,t_lift,lift_dx,lift_dz,lift_pitch,lift_h,reach_dx,reach_dz,reach_pitch,push_dx,push_dz,push_pitch,k_ik,k_py,reach_lat,tilt_step,lean_step,fe_step,t_reach,add_reach,drv_push,min_step,plant_load,plant_dx,plant_dy,x_plant
