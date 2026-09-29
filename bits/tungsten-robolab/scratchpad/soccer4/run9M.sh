#!/bin/sh
# balance search M: the lift and hold on the ramp base (pre-lift identical across candidates, so hold-phase changes are paired on the same states)
cd /Users/erik/tungsten/bits/tungsten-robolab
exec nice -n 10 .venv-myo/bin/python scratchpad/soccer4/search5.py --init params/myo_soccer_single_leg_310_ramp.txt \
  --set "cp_wash=1,cp_khs=-13.85968957031313,cp_tau=0.6" --out scratchpad/soccer4/s9M.txt --controller bin/challengers/soccer6-i \
  --seconds 7 --k_rand 24 --k_hard 0 --rand_lo 90000 --rand_hi 90400 --gens 30 --pop 12 --workers 4 --sigma 0.025 --leg_w 0.004 --leg_thr 40 --resume \
  --note "search M: lift + hold on the ramp base (bramp 0.05), hold-or-fall score at 7 s, 20 random training starts per generation" \
  --only b_unload,b_cp_tol,b_t_lift,b_add,b_st_hip,b_st_knee,b_st_ankle,b_sw_th,b_sw_knee,b_sw_ankle,b_sw_add,bc_in,cp_k,cp_lim,cp_limf,cp_x,cp_y,cp_ks,cp_ksf,cp_ka,cp_kaf,cp_kh,cp_khs,cp_tau,cp_ki,cp_h,sb_ksw,sb_kswv,sb_klb,sb_lean,sb_khp,sb_khpd,sb_kpr,sb_kprd,sb_pr_des,sb_rot_cc,sb_cc,sb_drv,sb_drv_abd,sb_g,sb_kyaw,sb_kyawd,fy_k,fy_lim
