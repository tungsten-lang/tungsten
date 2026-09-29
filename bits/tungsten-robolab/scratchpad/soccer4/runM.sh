#!/bin/sh
cd /Users/erik/tungsten/bits/tungsten-robolab
exec .venv-myo/bin/python scratchpad/soccer4/search4.py --init scratchpad/soccer4/M_init.txt \
  --out scratchpad/soccer4/sM.txt --stage p2 \
  --controller scratchpad/soccer4/ctl_v5M --seed_list 8545,8356,7914,7882,8331,7908,8087,7449,7453,8304,7505,7786,8391,8239,7885,8393,7469,8262,8502,7777,7562,8373,8552,7621,8224,8259,8242,8091,7750,7824,7992,7972,8481,7823,7411,7597,8564,8140,8355,7440 \
  --k 8 --gens 24 --pop 12 --workers 4 --seconds 10 --sigma 0.15 \
  --note "M: P2 pipeline: quasi-static approach steps (ap4, lift-tuned cp4 routine) to the kick spots, then the standing kick (k4), on P2 starts within 0.3 m of the P1 start" \
  --only k4_pdx,k4_pdy,k4_rdx,k4_rdy,k4_t_cock,s3_max_x,s3_max_y,s3_min_sep,s3_tol,s3_t_reach,s3_reach_max,s3_near,s3_load,s3_cp,s3_fall,s3_clr,s3_k_ik,s3_reach_dx,s3_reach_dz,s4_ahead,s4_back,s4_hmax,s4_turn,s4_v,s4_tmax,th_back,knee_back,ankle_back,th_k1,knee_k1,th_k2,knee_k2,t_swing,t_snap,hip_snap,drv_hip,drv_knee,g_kick,k_ky,kick_dy,ks_dx,ks_dz,b_t_shift,b_unload,tl_kp,tl_kd
