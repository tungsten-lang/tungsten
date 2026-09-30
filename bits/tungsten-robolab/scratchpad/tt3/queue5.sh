#!/bin/bash
# queue 5 (agent T3): gentle best-aim plans (nearest to the champion's realised normal) with the kinematic paddle and with the ideal pad-space arm servo (o5); then the robust-plan noise runs.
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
run() { TT3_PLAN="$1" TT3_CFG="$2" scratchpad/tt3/run_oracle.sh "$3" "$4" "$5"; }
run scratchpad/tt3/results/plan_bn0.1.json '{}' o4bn01 o4 "A B"
run scratchpad/tt3/results/plan_bn0.1.json '{"o5_tact":0.10,"o5_tau":0.12,"o5_hold":0.03}' o5bn01 o5 "A B"
run scratchpad/tt3/results/plan_bn0.25.json '{"o5_tact":0.10,"o5_tau":0.12,"o5_hold":0.03}' o5bn25 o5 "A B"
echo "$(date '+%F %T') QUEUE5 DONE" >> out/tt3/run_oracle.progress
for n in champ mid8 mid6 half spec; do
  TT3_PLAN=scratchpad/tt3/results/plan_rn_$n.json scratchpad/tt3/run_oracle.sh o4rn_$n o4 "A B"
done
echo "$(date '+%F %T') QUEUE5b DONE" >> out/tt3/run_oracle.progress
