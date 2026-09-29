#!/bin/sh
cd /Users/erik/tungsten/bits/tungsten-robolab
export MYO_SOCCER_MAX_TIME=8
exec .venv-myo/bin/python scratchpad/soccer4/search4.py --init scratchpad/soccer4/L_init.txt \
  --out scratchpad/soccer4/sL.txt --stage bal300 \
  --controller scratchpad/soccer4/ctl_v5L --seed0 93000 --k 16 --gens 16 --pop 12 --workers 4 --seconds 8 --sigma 0.12 \
  --note "L: the set, shift and lift into single support (8 s episodes, 16 fresh P2 starts per gen)" \
  --only b_t_set,bs_load,bs_v,bs_w,bs_tmax,b_t_shift,b_unload,b_cp_tol,bc_tmax,b_shift_add,b_kay,b_kayv,b_kax,b_kaxv,b_kst2,b_x,b_t_lift,b_sw_th,b_sw_knee,b_sw_add,b_sw_ankle,b_st_hip,b_st_knee,b_st_ankle,b_add,sb_x,sb_y,cp_k,cp_kh,cp_ks,cp_lim,cp_x,tl_kp,tl_kd,tl_cfull,live_axes,spring,k_lb,k_th,k_thd
