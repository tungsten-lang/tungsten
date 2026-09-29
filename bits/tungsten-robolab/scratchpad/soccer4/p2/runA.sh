#!/bin/sh
# P2 stage A (plant): the routine's right-leg stance into the parent's reach, on the P2 noise at the P1 position
cd /Users/erik/tungsten/bits/tungsten-robolab
exec .venv-myo/bin/python scratchpad/soccer4/search6.py --init scratchpad/soccer4/k6_init.txt --out scratchpad/soccer4/p2/A.txt \
  --controller bin/challengers/soccer6-i --noise 1.0 --w 0.0 --k 6 --gens 30 --pop 12 --workers 4 --seconds 6.5 --stage plant7 \
  --sigma 0.1 --seed0 92000 --resume --note "P2 stage A plant: k6 (routine right stance -> reach -> plant), noise 1, P1 position" \
  --only k6_t_hold,b_st_hip,b_st_knee,b_sw_th,b_sw_knee,b_sw_ankle,t_reach,reach_dx,reach_dz,reach_pitch,add_reach,push_dx,push_dz,push_pitch,drv_push,fe_step,tilt_step,lean_step,x_plant,plant_dx,plant_dy,k_ik,k_py,reach_lat,plant_load,min_step,k_ax_st,k_ay1,k_st1,k_roll,k_rolld,k_pr,g_st,drv_st,drv_post,x_step,k_comp
