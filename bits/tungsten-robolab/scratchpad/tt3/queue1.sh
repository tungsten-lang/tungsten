#!/bin/bash
# queue 1 (agent T3): the O4 variants on set B, then the execution-noise sweep of the best-aim kinematic paddle on sets A and B. One batch at a time.
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
for v in a a2 b bm; do
  TT3_PLAN=scratchpad/tt3/results/plan_$v.json scratchpad/tt3/run_oracle.sh o4$v o4 "B"
done
for n in champ pitch yaw vel pos half spec; do
  TT3_PLAN=scratchpad/tt3/results/plan_b_n$n.json scratchpad/tt3/run_oracle.sh o4bn_$n o4 "A B"
done
echo "$(date '+%F %T') QUEUE1 DONE" >> out/tt3/run_oracle.progress
