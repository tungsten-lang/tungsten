#!/bin/sh
# S9 (batting round 2): the BALANCED P95-body controller. S8b's swing (params/bat_r2_p95_s8.txt: 32.4 m/s, 48/48 hits) launches the balls at a mean 30-39 deg
# with a quarter of the hits above 60 deg (fair 35-36 of 48); the launch angle is ~ 36 + 11.5 x aim_n deg (aim_n = the ball's offset from the swing plane in
# cm; correlation 0.85-0.91), so the fix is a tighter aim: the launch cost is raised to 0.10 per degree beyond 8 off 20 (was 0.04 beyond 10) and the aim margin
# starts at 1.5 cm (was 3) at 1.0 per cm (was 0.5). Same 41 tunables, new training pitches (seeds 7300-7323, never used before), S8b's best as the start.
#   scratchpad/bat/s9.sh [workers] [budget]     -> params/search/bat_r2_s9.txt, out/bat_r2/s9.log
cd /Users/erik/tungsten/bits/tungsten-robolab
W=${1:-4}; B=${2:-2000}
export ROBOLAB_CONTROLLER=$PWD/bin/challengers/bat_r2-t8 BATREP_FLOW=4 BATREP_FLOW_CAP=2.5 BATREP_LAUNCH=0.10 BATREP_LAUNCH_CAP=8 BATREP_AIM=1.0 BATREP_AIM_CAP=1.5 ROBOLAB_PROFILE=p95 BAT_BODY=athlete
SEEDS=7300,7301,7302,7303,7304,7305,7306,7307,7308,7309,7310,7311,7312,7313,7314,7315,7316,7317,7318,7319,7320,7321,7322,7323
exec .venv/bin/python playground/search.py bat_rep --method sep_cma --budget $B --workers $W --sigma 0.05 --pop 16 --risk 0.25 --seconds 4.3 --seeds $SEEDS \
  --init params/bat_r2_p95_s8.txt \
  --only 'dw*,dshape_b,taim_z,taim_x,taim_z0,taim_x0,taim_ramp,prog_trig,train_end,train_lead,k_in,train_drv' \
  --box dshape_b=0.2:1.0,taim_z=2:9,taim_x=0:5,taim_z0=-0.05:0.2,taim_x0=-0.1:0.1,taim_ramp=0.5:1.1,prog_trig=0.2:0.26,train_end=-0.04:0.0,train_lead=0:0.035,k_in=0:0.12,train_drv=0.9:1.3 \
  --out params/search/bat_r2_s9.txt --log out/bat_r2/s9.jsonl
