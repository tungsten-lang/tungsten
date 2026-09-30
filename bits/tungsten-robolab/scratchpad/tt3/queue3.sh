#!/bin/bash
# queue 3 (agent T3): the pelvis / arm oracle variants on both sets, O3, then the robust-plan noise runs. One batch at a time.
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
export TT3_PASS1=out/tt3/logs_o0
run() { TT3_CFG="$1" scratchpad/tt3/run_oracle.sh "$2" "$3" "$4"; }
run '{}' o1 o1 "A B"
run '{"o1_vmax":1.5}' o1a o1 "A B"
run '{"o1_vend_file":"scratchpad/tt3/results/pelvis_vend_A.json"}' o1c o1 "A B"
run '{"o1_vend_file":"scratchpad/tt3/results/pelvis_vend_A.json","o1_vmax":1.5}' o1ca o1 "A B"
run '{}' o2 o2 "A B"
run '{"o2_gunit":1}' o2u o2 "A B"
run '{"o2_ref":"own","o2_smooth":0}' o2own0 o2 "A B"
run '{"o2_ref":"own","o2_smooth":2}' o2own2 o2 "A B"
run '{"o2_ref":"own","o2_smooth":4}' o2own4 o2 "A B"
run '{}' o3 o3 "A B"
run '{"o1_vend_file":"scratchpad/tt3/results/pelvis_vend_A.json"}' o3c o3 "A B"
echo "$(date '+%F %T') QUEUE3 DONE" >> out/tt3/run_oracle.progress
for n in champ mid8 mid6 half spec; do
  TT3_PLAN=scratchpad/tt3/results/plan_rn_$n.json scratchpad/tt3/run_oracle.sh o4rn_$n o4 "A B"
done
echo "$(date '+%F %T') QUEUE3b DONE" >> out/tt3/run_oracle.progress
