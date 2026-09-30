#!/bin/bash
# Post-verdict diagnostics (agent T2), LABELLED BEYOND-HUMAN ARM what-ifs on the 100 arena serves, unchanged champion. One at a time, 3 workers.
# each line of the list: tag strength speed activation [group: arm|hand|trunk|all]
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
while read -r tag s v a g; do
  [ -z "$tag" ] && continue
  echo "$(date '+%F %T') $tag ($s,$v,$a group ${g:-all}) start" >> out/tt2/run_diag.progress
  TT_ENV=P2 TT_TASK=myo_tt_beyond MYO_TT_BEYOND=9 MYO_TT_BEYOND_DIAG="$s,$v,$a" MYO_TT_BEYOND_GROUP="${g:-all}" TT_SAVE_LOG=out/tt2/logs_diag_$tag \
    nice -n 10 .venv-myo/bin/python playground/tt_eval.py --params params/myo_tt_p2_r10_c3.txt --controller bin/challengers/myo_tt_r10-n \
    --seeds 98000:98100 --out out/tt2/diag_${tag}_98000.jsonl --workers 3 > out/tt2/diag_${tag}_98000.summary 2> out/tt2/diag_${tag}_98000.err
  echo "$(date '+%F %T') $tag done: $(head -1 out/tt2/diag_${tag}_98000.summary | head -c 500)" >> out/tt2/run_diag.progress
done < "${1:-scratchpad/tt2/diag_list.txt}"
echo "$(date '+%F %T') ALL DONE" >> out/tt2/run_diag.progress
