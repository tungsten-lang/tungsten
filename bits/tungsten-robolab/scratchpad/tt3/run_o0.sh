#!/bin/bash
# O0 baseline (agent T3): the UNCHANGED champion (bin/challengers/myo_tt_r10-n + params/myo_tt_p2_r10_c3.txt), official task, fast path (verified identical to the standard path by agent T),
# serve sets A = 98000-98099 and B = 830000-830099, per-episode logs (TT_SAVE_LOG, read-only) = the pass-1 record of the oracles. 3 workers, nice 10.
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
for set in A B; do
  if [ $set = A ]; then S=98000:98100; else S=830000:830100; fi
  echo "$(date '+%F %T') O0 set $set start" >> out/tt3/run_o0.progress
  TT_ENV=P2 TT_SAVE_LOG=out/tt3/logs_o0 nice -n 10 .venv-myo/bin/python playground/tt_eval.py --params params/myo_tt_p2_r10_c3.txt \
    --controller bin/challengers/myo_tt_r10-n --seeds $S --out out/tt3/o0_$set.jsonl --workers 3 > out/tt3/o0_$set.summary 2> out/tt3/o0_$set.err
  echo "$(date '+%F %T') O0 set $set done: $(tail -1 out/tt3/o0_$set.summary | head -c 600)" >> out/tt3/run_o0.progress
done
echo "$(date '+%F %T') ALL DONE" >> out/tt3/run_o0.progress
