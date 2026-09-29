#!/bin/sh
cd /Users/erik/tungsten/bits/tungsten-robolab
exec .venv-myo/bin/python scratchpad/soccer4/search4.py --init params/myo_soccer_single_leg_tlh.txt \
  --out scratchpad/soccer4/sB.txt --stage bal \
  --controller scratchpad/soccer4/ctl_v4b --seed0 84000 --k 8 --gens 14 --pop 12 --workers 3 --seconds 10 --sigma 0.15 \
  --note "B: tlh (reference slopes) tuned on the rotcc champion" \
  --only tl_kp,tl_kd,tl_cap,tl_spin,tl_cancel,tl_kscale,tl_wfoot,tl_max,tl_ktr,tl_ksw,sb_rot_cc,sb_kha,sb_kst,sb_ksw,sb_klb,b_st_hip,b_sw_th,b_sw_add,b_add,sb_y,sb_x
