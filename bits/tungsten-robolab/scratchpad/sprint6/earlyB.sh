#!/bin/sh
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
SEEDS=$(cat out/sprint6/dev_small.txt)
WORKERS=6 scratchpad/sprint6/scan6.sh earlyB params/run_geary_v4_beyond_s5b.txt bin/challengers/run_gearz-s6e $SEEDS 6 "" \
  "lean_thr=-0.03,bal_cap=0.06,bal_rate=0.15,risk_gate=-0.025" \
  "lean_thr=-0.03,bal_cap=0.1,bal_rate=0.15,risk_gate=-0.025" \
  "lean_thr=-0.03,bal_cap=0.1,bal_rate=0.15,risk_gate=-0.025,risk_hip=0.3" \
  "lean_thr=-0.03,bal_cap=0.1,bal_rate=0.3,risk_gate=-0.025,risk_hip=0.3,risk_knee=-0.1" \
  "lean_thr=-0.03,bal_cap=0.15,bal_rate=0.1,risk_gate=-0.025,risk_hip=0.4,risk_spine=0.2" \
  "lean_thr=-0.03,bal_cap=0.03,bal_rate=0.1,risk_gate=-0.025,risk_hip=0.4" \
  "lean_thr=-0.03,bal_cap=0.0,risk_gate=-0.025,risk_hip=0.5,risk_ramp=0.5"
