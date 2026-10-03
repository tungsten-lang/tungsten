#!/bin/sh
# 30 Sep (main session): after the v5 (totals-kept) search es_v5_g3_s1 ends, its final incumbent on v5's own 44 UNSEEN flying starts (run_v5_a5x), same protocol as eval_final.sh.
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
while kill -0 "$(cat scratchpad/anat5/es_v5_g3_s1.pid)" 2>/dev/null; do sleep 10; done
echo "$(date '+%H:%M:%S') eval C1_final_v5_a5x" >> scratchpad/anat5/eval_final.progress
scratchpad/anat5/eval_fly.sh v5 scratchpad/anat5/es_v5_g3_s1.txt C1_final_v5_a5x run_v5_a5x 0-43 16 8 >> scratchpad/anat5/eval_final.progress 2>&1
echo "$(date '+%H:%M:%S') ALL DONE v5" >> scratchpad/anat5/eval_final.progress
