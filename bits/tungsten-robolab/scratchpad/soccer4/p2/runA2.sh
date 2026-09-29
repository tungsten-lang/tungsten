#!/bin/sh
# P2 stage A' (plant) with the round-4 terms (tlh, fyaw, cp4) active in the reach and kick: rk4 1
cd /Users/erik/tungsten/bits/tungsten-robolab
exec nice -n 10 .venv-myo/bin/python scratchpad/soccer4/search6.py --init scratchpad/soccer4/k6_init.txt --set "rk4=1" --out scratchpad/soccer4/p2/A2.txt \
  --controller bin/challengers/soccer6-i --noise 1.0 --w 0.0 --k 6 --gens 30 --pop 12 --workers 4 --seconds 6.5 --stage plant7 \
  --sigma 0.1 --seed0 92500 --resume --note "P2 stage A2 plant: k6 + rk4, noise 1, P1 position" \
  --only rk_head,rk_plant,rk_yawc,k6_t_hold,b_st_hip,b_st_knee,b_sw_th,b_sw_knee,b_sw_ankle,t_reach,reach_dx,reach_dz,reach_pitch,add_reach,push_dx,push_dz,push_pitch,drv_push,fe_step,tilt_step,lean_step,x_plant,plant_dx,plant_dy,k_ik,k_py,reach_lat,plant_load,min_step,k_ax_st,k_ay1,k_st1,k_roll,k_rolld,k_pr,g_st,drv_st,drv_post,x_step,k_comp
