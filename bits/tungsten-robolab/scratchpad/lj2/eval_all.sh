#!/bin/sh
# per-start evaluation of a params file + controller on the three v4 robust trials (16 arena starts, 32 fresh, 96 fresh), 2 workers.
# usage: eval_all.sh <params> <controller> <tag> [task]
cd /Users/erik/tungsten/bits/tungsten-robolab
P=$1; C=$2; T=$3; TASK=${4:-long_jump_v4_p95b}
for tr in long_jump_v4_p95_robust long_jump_v4_p95_robust32 long_jump_v4_p95_robust96; do
  n=$(echo $tr | sed 's/long_jump_v4_p95_//')
  .venv/bin/python playground/long_jump_eval.py $tr --params $P --controller $C --task $TASK --workers 4 --out scratchpad/lj2/eval_${T}_${n}.json > scratchpad/lj2/eval_${T}_${n}.txt 2>&1
  tail -1 scratchpad/lj2/eval_${T}_${n}.txt | cut -c1-300
done
