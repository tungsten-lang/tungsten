#!/bin/bash
# Step (a): the UNCHANGED champion (bin/challengers/myo_tt_r10-n + params/myo_tt_p2_r10_c3.txt) on the 100 arena serves 98000-98099 at rungs 1, 2, 3 and 0 (the yardstick),
# per-episode logs (TT_SAVE_LOG, read-only) for the noise decomposition. One rung at a time, 3 workers. LABELLED BEYOND-HUMAN ARM for rungs > 0.
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
for r in ${RUNGS:-1 2 3 0}; do
  echo "$(date '+%F %T') rung $r start" >> out/tt2/run_a.progress
  TT_ENV=P2 TT_TASK=myo_tt_beyond MYO_TT_BEYOND=$r TT_SAVE_LOG=out/tt2/logs_r$r \
    nice -n 10 .venv-myo/bin/python playground/tt_eval.py --params params/myo_tt_p2_r10_c3.txt --controller bin/challengers/myo_tt_r10-n \
    --seeds 98000:98100 --out out/tt2/champ_r${r}_98000.jsonl --workers 3 > out/tt2/champ_r${r}_98000.summary 2> out/tt2/champ_r${r}_98000.err
  echo "$(date '+%F %T') rung $r done: $(tail -1 out/tt2/champ_r${r}_98000.summary | head -c 400)" >> out/tt2/run_a.progress
done
echo "$(date '+%F %T') ALL DONE" >> out/tt2/run_a.progress
