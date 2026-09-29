#!/bin/sh
cd /Users/erik/tungsten/bits/tungsten-robolab
exec .venv-myo/bin/python scratchpad/soccer4/search4.py --init scratchpad/soccer4/w1_init.txt \
  --out scratchpad/soccer4/sW1.txt --stage walk --env myoChallengeSoccerP1-v0 \
  --controller scratchpad/soccer4/ctl_w1 --fixed_seeds 700 --gens 40 --pop 14 --workers 1 --seconds 6 --sigma 0.15 \
  --note "W1: the chase-tag walker on the soccer body, walking 0.6 m from the P1 start" \
  --only kp,kd,pitch_des,tq_kp,tq_kd,rq_kp,rq_kd,yq_kp,yq_kd,hip_lead,t_st,k_st,a_st,g_st,g_ank,d_push,t_push,k_push,a_push,drv_push,t_lift,psi_lift,k_lift,drv_lift,t_reach,psi_land,k_reach,cv,cd,ab_land,cv_lat,cd_lat,v_walk,shift,k_shift,k_lean,d_lean,drv_abd,drv_vas,w_tp,w_kth,w_kthd,w_klb,w_fe,w_ktone,th_on,yq_kp_t,tr_max_t
