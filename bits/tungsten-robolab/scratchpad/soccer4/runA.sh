#!/bin/sh
cd /Users/erik/tungsten/bits/tungsten-robolab
exec .venv-myo/bin/python scratchpad/soccer4/search4.py --init params/myo_soccer_single_leg_rotcc.txt \
  --out scratchpad/soccer4/sA.txt --set "tlh=1,sense_arms=1,hg=1,fyaw=1" --stage bal \
  --controller scratchpad/soccer4/ctl_v4a --seed0 82000 --k 6 --gens 18 --pop 12 --workers 3 --seconds 12 --sigma 0.12 \
  --note "A: live arms + tlh + hip guard + fyaw on the rotcc champion" \
  --only tl_kp,tl_kd,tl_cap,tl_cancel,tl_wfoot,tl_kscale,tl_max,hg_min,hg_k,fy_k,sb_kha,sb_khav,sb_kpr,sb_kprd,sb_khp,sb_khpd,sb_ksw,sb_kswv,sb_klb,sb_lean,sb_x,sb_y,sb_kst,sb_kstv,sb_kax,sb_kaxv,sb_drv,sb_drv_abd,sb_cc,sb_rot_cc,sb_g,b_st_hip,b_st_knee,b_st_ankle,b_add,b_sw_th,b_sw_knee,b_sw_add,b_shift_add,b_kay,b_kayv,b_t_shift,b_hold
