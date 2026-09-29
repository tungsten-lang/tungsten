#!/bin/sh
cd /Users/erik/tungsten/bits/tungsten-robolab
exec .venv-myo/bin/python scratchpad/soccer4/search4.py --init scratchpad/soccer4/p2_ap4_init.txt \
  --out scratchpad/soccer4/sC.txt --stage ap3 \
  --controller scratchpad/soccer4/ctl_v4c --seed0 6000 --k 6 --gens 16 --pop 12 --workers 3 --seconds 14 --sigma 0.15 \
  --note "C: ap4 turning approach (tlh, fyaw) on P2" \
  --only s3_t_reach,s3_reach_max,s3_near,s3_load,s3_cp,s3_cpx,s3_fall,s3_clr,s3_k_ik,s3_t_mid,s3_t_hold,s3_min_sep,s3_max_y,s4_ahead,s4_back,s4_turn,s4_hmax,b_t_shift,b_t_lift,b_cp_tol,b_unload,b_shift_add,tl_kp,tl_kd,fy_k,sb_y,sb_kst,sb_kha,sb_ksw,b_sw_th,b_sw_knee
