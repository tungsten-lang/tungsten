#!/bin/sh
# clearance search C3 (9/29): as C2 but a heavier force weight (0.06 per N), 6 starts a generation, another random seed and a wider box
# (adds the swing hip's flexion/adduction drive and the stance ankle offsets): look for a posture with NO inter-leg contact that still holds.
cd /Users/erik/tungsten/bits/tungsten-robolab
exec .venv-myo/bin/python scratchpad/soccer4/search5.py --init params/myo_soccer_single_leg_310_shc.txt \
  --out scratchpad/soccer4/s9C3.txt --controller bin/challengers/soccer6-p \
  --seconds 5 --k_rand 6 --k_hard 0 --rand_lo 90000 --rand_hi 90400 --gens 30 --pop 8 --workers 4 --sigma 0.06 --leg_w 0.06 --leg_thr 0 --rseed 7 --resume \
  --note "clearance search C3: heavier force weight, 6 starts, rseed 7 (shift-brake base)" \
  --only b_sw_th,b_sw_knee,b_sw_ankle,b_sw_add,b_add,b_st_hip,b_st_knee,b_st_ankle,sb_lean,sb_drv_abd,sb_drv,sb_ksw,sb_kswv,sb_khp,sb_klb,cp_ks,cp_ka,b_t_lift,bc_in
