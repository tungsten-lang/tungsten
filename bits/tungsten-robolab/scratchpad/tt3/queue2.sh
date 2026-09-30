#!/bin/bash
# queue 2 (agent T3): the ROBUST best-aim kinematic paddle under execution noise (sim-confirmed tolerance curve), after queue 1.
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
until grep -q "QUEUE1 DONE" out/tt3/run_oracle.progress; do sleep 3; done
for n in champ mid8 mid6 half spec; do
  TT3_PLAN=scratchpad/tt3/results/plan_rn_$n.json scratchpad/tt3/run_oracle.sh o4rn_$n o4 "A B"
done
echo "$(date '+%F %T') QUEUE2 DONE" >> out/tt3/run_oracle.progress
