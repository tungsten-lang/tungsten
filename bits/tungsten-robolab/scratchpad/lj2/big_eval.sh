#!/bin/sh
# 480 never-used starts (seeds 10001-10480) for the final robust programs, controller c3, 4 workers, one evaluation at a time.
# usage: big_eval.sh [seeds]   -> scratchpad/lj2/eval_big_<tag>.json / .txt
cd /Users/erik/tungsten/bits/tungsten-robolab
S=${1:-10001-10480}
for tag in final2 final1 final3; do
  .venv/bin/python playground/long_jump_eval.py long_jump_v4_p95_robust96 --params params/long_jump_v4_gear_$tag.txt \
    --controller bin/challengers/long_jump_run-c3 --task long_jump_v4_p95b --seeds $S --workers 4 \
    --out scratchpad/lj2/eval_big_$tag.json > scratchpad/lj2/eval_big_$tag.txt 2>&1
  tail -1 scratchpad/lj2/eval_big_$tag.txt | cut -c1-300
done
echo BIG_DONE
