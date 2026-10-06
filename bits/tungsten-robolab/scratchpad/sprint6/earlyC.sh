#!/bin/sh
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
SEEDS=$(cat out/sprint6/dev_small.txt)
WORKERS=6 scratchpad/sprint6/scan6.sh earlyC params/run_geary_v4_beyond_s5b.txt bin/challengers/run_gearz-s6e $SEEDS 6 "" \
  "stall_t=0.3,stall_x=0.0,stall_spine=0.3,stall_ramp=0.4" \
  "stall_t=0.3,stall_x=0.0,stall_spine=0.5,stall_ramp=0.4" \
  "stall_t=0.3,stall_x=0.0,stall_hip=0.3,stall_ramp=0.4" \
  "stall_t=0.3,stall_x=0.0,stall_spine=0.3,stall_hip=0.3,stall_ramp=0.4" \
  "stall_t=0.3,stall_x=0.0,stall_arm=1.2,stall_ramp=0.4" \
  "stall_t=0.3,stall_x=0.0,stall_knee=-0.1,stall_ramp=0.4" \
  "stall_t=0.5,stall_x=0.0,stall_spine=0.4,stall_ramp=0.8"
