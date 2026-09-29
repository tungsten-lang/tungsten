#!/bin/sh
# P2 stage A3 (plant) with the lean phase k7: routine right stance -> lean -> reach -> plant, noise 1 at the P1 position
cd /Users/erik/tungsten/bits/tungsten-robolab
exec nice -n 10 .venv-myo/bin/python scratchpad/soccer4/search6.py --init scratchpad/soccer4/k6_init.txt \
  --set "k7=1,k7_lean=0.3,k7_go=0.1,k7_t_max=1.0,k7_t_lean=0.4" --out scratchpad/soccer4/p2/A3.txt \
  --controller bin/challengers/soccer6-j --noise 1.0 --w 0.0 --k 6 --gens 40 --pop 12 --workers 4 --seconds 6.5 --stage plant7 \
  --sigma 0.1 --seed0 93000 --resume --note "P2 stage A3 plant: k6 + k7 lean, noise 1, P1 position" \
  --only k7_lean,k7_t_lean,k7_go,k7_t_max,k6_t_hold,b_st_hip,b_st_knee,b_sw_th,b_sw_knee,b_sw_ankle,t_reach,reach_dx,reach_dz,reach_pitch,add_reach,push_dx,push_dz,push_pitch,drv_push,fe_step,tilt_step,lean_step,x_plant,plant_dx,plant_dy,k_ik,k_py,reach_lat,plant_load,min_step,k_ax_st,k_ay1,k_st1,k_roll,k_rolld,k_pr,g_st,drv_st,drv_post,x_step,k_comp,cp_x,cp_limf
