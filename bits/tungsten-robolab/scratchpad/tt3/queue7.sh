#!/bin/bash
# queue 7 (agent T3): robust-plan kinematic paddle under tighter noise and one noise source at a time (sim-confirmed tolerance), then the decelerating ideal pad-space arm.
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
for n in tight tighter pitch yaw vel pos; do
  TT3_PLAN=scratchpad/tt3/results/plan_rn_$n.json scratchpad/tt3/run_oracle.sh o4rn_$n o4 "A B"
done
echo "$(date '+%F %T') QUEUE7 DONE" >> out/tt3/run_oracle.progress
