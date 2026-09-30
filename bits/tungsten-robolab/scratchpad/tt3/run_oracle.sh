#!/bin/bash
# One oracle batch (agent T3): TAG MODE [sets] with the env of the oracle (TT3_CFG, TT3_PLAN, TT3_PASS1 from the caller). 3 workers, nice 10, TT_SAVE_LOG for the noise measures,
# TT3_LOG for the oracle's own per-tick log. Serve sets A = 98000-98099, B = 830000-830099. Output out/tt3/<TAG>_{A,B}.jsonl, summaries, progress out/tt3/run_oracle.progress.
# usage: TT3_CFG='{...}' scratchpad/tt3/run_oracle.sh o1 o1 "A B"
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
TAG=$1; MODE=$2; SETS=${3:-"A B"}
for set in $SETS; do
  rm -f out/tt3/${TAG}_$set.jsonl   # never resume an old run of the same tag (the evaluator skips finished seeds)
  if [ $set = A ]; then S=98000:98100; else S=830000:830100; fi
  echo "$(date '+%F %T') $TAG set $set start (MYO_TT_ORACLE=$MODE cfg=$TT3_CFG)" >> out/tt3/run_oracle.progress
  MYO_TT_ORACLE=$MODE TT_TASK=myo_tt_oracle TT_ENV=P2 TT_SAVE_LOG=out/tt3/logs_$TAG TT3_LOG=out/tt3/orc_$TAG nice -n 10 .venv-myo/bin/python playground/tt_eval.py \
    --params params/myo_tt_p2_r10_c3.txt --controller bin/challengers/myo_tt_r10-n --seeds $S --out out/tt3/${TAG}_$set.jsonl --workers 3 > out/tt3/${TAG}_$set.summary 2> out/tt3/${TAG}_$set.err
  echo "$(date '+%F %T') $TAG set $set done: $(grep '^{' out/tt3/${TAG}_$set.summary | tail -1 | head -c 700)" >> out/tt3/run_oracle.progress
done
