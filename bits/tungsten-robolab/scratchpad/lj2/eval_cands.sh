#!/bin/sh
# evaluate params files on a seed range with c3, one at a time. usage: eval_cands.sh <seeds> <tag> <workers> <params> [<params> ...]  -> scratchpad/lj2/eval_cand_<tag>_<basename>.json
cd /Users/erik/tungsten/bits/tungsten-robolab
S=$1; TAG=$2; W=$3; shift 3
for p in "$@"; do
  b=$(basename $p .txt)
  f=scratchpad/lj2/eval_cand_${TAG}_$b
  .venv/bin/python playground/long_jump_eval.py long_jump_v4_p95_robust96 --params $p --controller bin/challengers/long_jump_run-c3 \
    --task long_jump_v4_p95b --seeds $S --workers $W --out $f.json > $f.txt 2>&1
  echo "$b: $(grep '^MEAN' $f.txt | cut -c1-100)"
done
echo CANDS_DONE
