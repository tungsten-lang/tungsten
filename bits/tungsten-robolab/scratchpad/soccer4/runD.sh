#!/bin/sh
cd /Users/erik/tungsten/bits/tungsten-robolab
exec .venv-myo/bin/python scratchpad/soccer4/search4.py --init params/myo_soccer_single_leg_catch.txt \
  --out scratchpad/soccer4/sD.txt --stage bal \
  --controller scratchpad/soccer4/ctl_v4f --seed0 85000 --k 8 --gens 16 --pop 12 --workers 3 --seconds 14 --sigma 0.15 \
  --note "D: falls caught by stepping (bcatch) on the tlh variant" \
  --only bc_in,b_t_down,b_load,b_t_mid,b_t_shift,b_cp_tol,b_unload,b_shift_add,b_kay,b_kayv,b_kax,b_kaxv,b_kst2,b_hold,sb_y,sb_kst,sb_kha,tl_kp,tl_kd,tl_wfoot
