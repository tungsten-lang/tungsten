#!/bin/bash
# The round-9 live-tracking controller (bin/challengers/myo_tt_r9-a; its per-side practised params) on serve set A (98000-98099) with per-episode logs,
# for scratchpad/tt4/plane_probe.py: does muscle-level tracking (the contraction vector that reaches the commanded posture) hold the paddle plane better?
# Same recipe as scratchpad/tt3/run_o0.sh (the champion's baseline on the same serves). 3 workers, nice 10. Read-only with respect to every champion and trial.
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
mkdir -p out/tt4
for side in fh bh; do
  echo "$(date '+%F %T') lt_$side start" >> out/tt4/run_lt.progress
  TT_ENV=P2 TT_SAVE_LOG=out/tt4/logs_lt_$side nice -n 10 .venv-myo/bin/python playground/tt_eval.py --params params/myo_tt_p2_r9_lt_$side.txt \
    --controller bin/challengers/myo_tt_r9-a --seeds 98000:98100 --out out/tt4/lt_$side.jsonl --workers 3 > out/tt4/lt_$side.summary 2> out/tt4/lt_$side.err
  echo "$(date '+%F %T') lt_$side done: $(tail -1 out/tt4/lt_$side.summary | head -c 400)" >> out/tt4/run_lt.progress
done
echo "$(date '+%F %T') ALL DONE" >> out/tt4/run_lt.progress
