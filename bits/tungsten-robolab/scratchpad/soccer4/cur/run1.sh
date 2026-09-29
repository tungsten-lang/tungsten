#!/bin/sh
cd /Users/erik/tungsten/bits/tungsten-robolab
exec .venv-myo/bin/python scratchpad/soccer4/search4.py --init scratchpad/soccer4/cur/s0_init.txt \
  --out scratchpad/soccer4/cur/s1.txt --stage stork --set "stage=0.5" \
  --controller scratchpad/soccer4/cur/ctl --seed_list $(cat scratchpad/soccer4/near_train.txt | sed 's/,$//') \
  --k 8 --gens 20 --pop 14 --workers 4 --seconds 5 --sigma 0.15 \
  --note "curriculum stage 1 (stork): settle, shift onto the right foot, lift the left, stand on the right leg" \
  --only b_t_set,bs_v,bs_tmax,t_shift,shift_x,shift_y,unload,shift_add,shift_st,d_go,k_st2,k_ax_st,x_step,t_lift,lift_dx,lift_dz,lift_pitch,lean_step,k_ay1,k_st1,k_roll,k_rolld,k_pr,k_prd,k_hp,k_hpd,k_comp,k_ay,k_ayv
