#!/bin/sh
cd /Users/erik/tungsten/bits/tungsten-robolab
export MYO_SOCCER_MAX_TIME=30
exec .venv-myo/bin/python scratchpad/soccer4/search4.py --init scratchpad/soccer4/g_init.txt \
  --out scratchpad/soccer4/sG.txt --stage bal300 \
  --controller scratchpad/soccer4/ctl_v4g --seed0 86000 --k 6 --gens 22 --pop 14 --workers 4 --seconds 30 --sigma 0.15 \
  --note "G: long one-leg balance on the sensed COP (cp4: capture point, COP servo, hip strategy), live hip-rotation arms, tlh, catch" \
  --only cp_k,cp_lim,cp_limf,cp_x,cp_y,cp_ks,cp_ksf,cp_ka,cp_kaf,cp_kh,cp_ki,cp_h,sb_kpr,sb_kprd,sb_pr_des,sb_klb,sb_lean,sb_ksw,sb_kswv,sb_khp,sb_khpd,b_cp_tol,b_t_lift,b_t_shift,b_sw_th,b_sw_knee,b_sw_add,b_st_hip,b_st_knee,b_add,sb_drv_abd,sb_cc,sb_g,tl_kp,tl_kd,bc_in
