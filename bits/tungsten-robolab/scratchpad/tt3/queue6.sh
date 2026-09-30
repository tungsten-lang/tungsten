#!/bin/bash
# queue 6 (agent T3): the ideal pad-space arm servo (o5) on the gentle best-aim plan (bn0.1), two timings, both sets; then the same plan with the champion's noise excluded (puppet) already run (o4bn01).
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
run() { TT3_PLAN="$1" TT3_CFG="$2" scratchpad/tt3/run_oracle.sh "$3" "$4" "$5"; }
run scratchpad/tt3/results/plan_bn0.1.json '{"o5_tact":0.30,"o5_tau":0.10,"o5_hold":0.03,"o5_wrot":0.30}' o5a o5 "A B"
run scratchpad/tt3/results/plan_bn0.1.json '{"o5_tact":0.32,"o5_tau":0.08,"o5_hold":0.03,"o5_wrot":0.30}' o5b o5 "A B"
run scratchpad/tt3/results/plan_bn0.1.json '{"o5_tact":0.30,"o5_tau":0.10,"o5_hold":0.03,"o5_wrot":0.30,"o2_taumax":100}' o5cap o5 "A B"
echo "$(date '+%F %T') QUEUE6 DONE" >> out/tt3/run_oracle.progress
for n in champ mid8 mid6 half spec; do
  TT3_PLAN=scratchpad/tt3/results/plan_rn_$n.json scratchpad/tt3/run_oracle.sh o4rn_$n o4 "A B"
done
echo "$(date '+%F %T') QUEUE6b DONE" >> out/tt3/run_oracle.progress
