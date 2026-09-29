#!/bin/sh
cd /Users/erik/tungsten/bits/tungsten-robolab
export MYO_SOCCER_MAX_TIME=20
exec .venv-myo/bin/python scratchpad/soccer4/search4.py --init scratchpad/soccer4/j2_init.txt \
  --out scratchpad/soccer4/sJ2.txt --stage bal300 \
  --controller scratchpad/soccer4/ctl_v5e --seed0 92000 --k 10 --gens 14 --pop 12 --workers 4 --seconds 20 --sigma 0.12 \
  --note "J2: the lift into a long hold (20 s): sagittal hip strategy (cp_khf), live flexion arms (live_axes), load-based mid-stance (bdown) for retries" \
  --only cp_khf,live_axes,bd_in,cp_k,cp_ka,cp_kaf,cp_limf,cp_x,cp_kh,cp_ks,sb_khp,sb_khpd,sb_x,b_t_set,bs_load,bs_v,bs_w,b_t_shift,b_unload,b_cp_tol,b_t_lift,b_sw_th,b_sw_knee,b_sw_add,b_st_hip,b_st_knee,b_st_ankle,b_add,tl_kp,tl_kd,bc_in,b_kax,b_kaxv,b_x
