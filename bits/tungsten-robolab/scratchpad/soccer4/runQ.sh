#!/bin/sh
cd /Users/erik/tungsten/bits/tungsten-robolab
exec .venv-myo/bin/python scratchpad/soccer4/search4.py --init scratchpad/soccer4/Q_init.txt \
  --out scratchpad/soccer4/sQ.txt --stage step \
  --controller scratchpad/soccer4/ctl_v7e --seed0 93100 --k 8 --gens 30 --pop 14 --workers 4 --seconds 8 --sigma 0.15 \
  --note "Q: the approach's quasi-static steps on the round-5 one-leg routine (cp4, settled mid-stances), fresh P2 starts" \
  --only b_t_shift,b_unload,b_cp_tol,b_t_lift,s3_t_reach,s3_reach_max,s3_near,s3_load,s3_cp,s3_cpx,s3_fall,s3_clr,s3_k_ik,s3_k_py,s3_reach_dx,s3_reach_dz,s3_t_mid,s4_ahead,s4_back,s4_turn,s4_knee,s4_hip,s3_min_sep,s3_max_y,cp_k,cp_kh,cp_ks,cp_khf,tl_kp,tl_kd,tl_cfull,fy_k,sb_x,sb_y,b_sw_th,b_sw_knee,b_sw_add,b_shift_add,sb_ksw,sb_klb
