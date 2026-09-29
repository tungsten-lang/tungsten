#!/bin/sh
# E1k: the kick's follow-through with the single-leg routine's stance terms (kr 1: cp4 + tlh after the touch) and the landing/recovery chunks, from the
# touch checkpoints of the noisy phase-1 dumps whose contact was good (noise 0.05 and 0.1, seeds 5000-5047, dumps with the arm sensors).
cd /Users/erik/tungsten/bits/tungsten-robolab
exec .venv-myo/bin/python scratchpad/kick/ksearch.py --init params/myo_kick_kr0.txt --controller bin/challengers/kick-a5 --kind touch --good \
  --dir kbase --glob 'kbase_n0.05_*' --glob 'kbase_n0.1_*' --seeds 5000:5048 \
  --only t_follow,th_fol,knee_fol,drv_brake,drv_post,th_land,knee_land,ankle_land,rec_ldx,rec_rdx,rec_dz,fe_rec,t_rec,cp_k,cp_kh,cp_ks,cp_ksf,cp_ka,cp_kaf,cp_x,cp_y,cp_lim,cp_limf,tl_kp,tl_kd,tl_cfull,tl_wfoot,sb_ds_load \
  --out scratchpad/kick/out/E1k.txt --gens 30 --pop 12 --sigma 0.12 --seed 3 --note "E1k kr recovery from touch checkpoints, noisy P1 dumps 0.05/0.1 seeds 5000-5047"
