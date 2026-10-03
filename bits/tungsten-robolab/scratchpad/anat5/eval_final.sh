#!/bin/sh
# 30 Sep (main session): unseen-start validation of the runs A5's queue never reached, with A5's own protocol (eval_fly.sh: the 44 UNSEEN v4 gear-2 flying starts `run_v4_a5x`,
# 16 s, tail from 8 s, as fly_A1_u1000_v4_a5x etc.): the second v4 control seed (es_v4_g3_s2), and the final incumbents of v5b seeds 1 and 2. Paired tables: abtable.py --pair.
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
for spec in "v4 es_v4_g3_s2 A2_final_v4_a5x" "v5b es_v5b_g3_s1 B1_final_v4_a5x" "v5b es_v5b_g3_s2 B2_final_v4_a5x"; do
  set -- $spec
  echo "$(date '+%H:%M:%S') eval $3" >> scratchpad/anat5/eval_final.progress
  scratchpad/anat5/eval_fly.sh $1 scratchpad/anat5/$2.txt $3 run_v4_a5x 0-43 16 8 >> scratchpad/anat5/eval_final.progress 2>&1
done
echo "$(date '+%H:%M:%S') ALL DONE" >> scratchpad/anat5/eval_final.progress
