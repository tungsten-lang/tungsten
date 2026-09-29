#!/bin/sh
# S10 (batting round 2): the ATHLETE body, S3's swing retuned over the S8 tunables (41: drive profile, taim, timing) PLUS the leg/stride parameters that a one-at-a-time scan around S3
# (`evalcal.py ... --sets`, out/bat_r2/legscan1.log in LOG.md) found to matter: leg_swing_kp / leg_swing_kd (+0.19 m/s each alone, flow +0.05-0.09), stride_at (0.40: +0.20, flow +0.14, aim shift),
# train_legs (0.9: +0.08), train_legs_ease, drv_stride (0.8: flow -0.04), lift_at (0.14: flow -0.06 for nothing else), step_delay and dur_stride (both move the aim); hips/leglift durations, drv_hips and hips_lead
# do nothing. Objective as S9 (launch cost 0.10 per degree beyond 8 off 20, aim margin 1.0 per cm beyond 1.5) with the flow term anchored at S3's own flow (cap 2.35, 4 per unit), so a faster swing
# may not be a less smooth one. New training pitches seeds 7400-7423.
#   scratchpad/bat/s10.sh [workers] [budget] [init params] [tag]     -> params/search/bat_r2_<tag>.txt, out/bat_r2/<tag>.jsonl (defaults: 4, 2000, params/bat_r2_s3.txt, s10)
cd /Users/erik/tungsten/bits/tungsten-robolab
W=${1:-4}; B=${2:-2000}; INIT=${3:-params/bat_r2_s3.txt}; TAG=${4:-s10}
export ROBOLAB_CONTROLLER=$PWD/bin/challengers/bat_r2-t8 BATREP_FLOW=4 BATREP_FLOW_CAP=2.35 BATREP_LAUNCH=0.10 BATREP_LAUNCH_CAP=8 BATREP_AIM=1.0 BATREP_AIM_CAP=1.5 BAT_BODY=athlete
SEEDS=7400,7401,7402,7403,7404,7405,7406,7407,7408,7409,7410,7411,7412,7413,7414,7415,7416,7417,7418,7419,7420,7421,7422,7423
exec .venv/bin/python playground/search.py bat_rep --method sep_cma --budget $B --workers $W --sigma 0.05 --pop 16 --risk 0.25 --seconds 4.3 --seeds $SEEDS \
  --init $INIT \
  --only 'dw*,dshape_b,taim_z,taim_x,taim_z0,taim_x0,taim_ramp,prog_trig,train_end,train_lead,k_in,train_drv,leg_swing_kp,leg_swing_kd,stride_at,train_legs,train_legs_ease,drv_stride,lift_at,step_delay,dur_stride' \
  --box dshape_b=0.2:1.0,taim_z=2:9,taim_x=0:5,taim_z0=-0.05:0.2,taim_x0=-0.1:0.1,taim_ramp=0.5:1.1,prog_trig=0.2:0.26,train_end=-0.04:0.0,train_lead=0:0.035,k_in=0:0.12,train_drv=0.9:1.3,leg_swing_kp=0.5:3,leg_swing_kd=0.02:0.16,stride_at=0.38:0.5,train_legs=0.8:1.5,train_legs_ease=0:0.15,drv_stride=0.3:1.0,lift_at=0.09:0.18,step_delay=0.17:0.19,dur_stride=0.28:0.34 \
  --out params/search/bat_r2_$TAG.txt --log out/bat_r2/$TAG.jsonl
