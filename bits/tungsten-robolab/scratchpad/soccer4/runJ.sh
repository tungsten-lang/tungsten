#!/bin/sh
cd /Users/erik/tungsten/bits/tungsten-robolab
exec .venv-myo/bin/python scratchpad/soccer4/search4.py --init scratchpad/soccer4/j_init.txt \
  --out scratchpad/soccer4/sJ.txt --stage bal \
  --controller scratchpad/soccer4/ctl_v5c --seed0 91000 --k 8 --gens 18 --pop 12 --workers 4 --seconds 14 --sigma 0.15 \
  --note "J: the transitions (settle, shift, lift, placed put-down, second shift) of the cp4 single-leg routine" \
  --only b_t_set,bs_load,bs_v,bs_w,bs_tmax,b_t_shift,b_unload,b_cp_tol,bc_tmax,b_shift_add,b_kay,b_kayv,b_kax,b_kaxv,b_kst2,b_x,b_t_lift,b_t_down,b_load,b_t_mid,bp_k,bp_kf,bp_out,fy_k,bc_in,sb_x,sb_y,cp_k,cp_kh,tl_kp,tl_kd,b_sw_th,b_sw_knee,b_sw_add,tl_cfull,fy_lim
