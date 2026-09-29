#!/bin/sh
# standing kick from the robust left stance (feet 0.45 m behind the ball at the start, P2 noise 1): how hard can it be struck?
cd /Users/erik/tungsten/bits/tungsten-robolab
exec nice -n 10 .venv-myo/bin/python scratchpad/soccer4/search6.py --init scratchpad/soccer4/k4_init.txt --out scratchpad/soccer4/p2/K4.txt \
  --controller bin/challengers/soccer6-k --noise 1.0 --w 0.0 --dx0 0.627 --k 6 --gens 40 --pop 12 --workers 4 --seconds 6.5 --stage speed \
  --sigma 0.1 --seed0 94000 --resume --note "standing kick from the left stance, feet 0.45 m behind the ball, noise 1" \
  --only th_back,knee_back,ankle_back,th_k1,knee_k1,ankle_k,th_k2,knee_k2,hip_snap,drv_hip,drv_knee,t_swing,t_snap,k4_t_cock,k4_tmax,add_k,k_ky,kick_dy,rot_k,g_kick,ks_dx,ks_dz,ks_pitch,drv_st,k_ay1,k_st1,k_roll,k_rolld,k_pr,k_ax_st,cp_kh,cp_ks,cp_ka,cp_x
