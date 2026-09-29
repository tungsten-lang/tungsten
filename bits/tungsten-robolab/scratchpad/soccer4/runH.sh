#!/bin/sh
cd /Users/erik/tungsten/bits/tungsten-robolab
export MYO_SOCCER_MAX_TIME=30
exec .venv-myo/bin/python scratchpad/soccer4/search4.py --init scratchpad/soccer4/h_init.txt \
  --out scratchpad/soccer4/sH.txt --stage bal300 \
  --controller scratchpad/soccer4/ctl_v4i --seed0 87000 --k 8 --gens 20 --pop 14 --workers 4 --seconds 30 --sigma 0.12 \
  --note "H: the transition into single support (shift, capture, lift) under the cp4 hold that stands 300 s" \
  --only b_t_shift,b_unload,b_cp_tol,bc_tmax,b_shift_add,b_kay,b_kayv,b_kax,b_kaxv,b_kst2,b_x,sb_x,sb_y,b_t_lift,b_sw_th,b_sw_knee,b_sw_add,b_add,b_st_hip,b_st_knee,b_st_ankle,cp_k,cp_kh,cp_ks,cp_ksf,cp_ki,cp_lim,bc_in,tl_kp,tl_kd
