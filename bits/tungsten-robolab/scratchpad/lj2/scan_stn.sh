#!/bin/sh
# steering horizon on fresh starts with the frozen final2 program (no retraining): j_st_n = how many steps before the penultimate touchdown the planner starts nudging.
# usage: scan_stn.sh <seeds> <tag> <spec> [<spec> ...]   spec = k=v[,k=v]   -> scratchpad/lj2/eval_stn_<tag>_<spec>.json, one evaluation at a time, 4 workers
cd /Users/erik/tungsten/bits/tungsten-robolab
S=$1; TAG=$2; shift 2
for spec in "$@"; do
  f=scratchpad/lj2/eval_stn_${TAG}_$(echo $spec | tr ',=' '__')
  .venv/bin/python playground/long_jump_eval.py long_jump_v4_p95_robust96 --params params/long_jump_v4_gear_final2.txt \
    --controller bin/challengers/long_jump_run-c3 --task long_jump_v4_p95b --seeds $S --set "$spec" --workers 4 \
    --out $f.json > $f.txt 2>&1
  echo "$spec: $(grep '^MEAN' $f.txt | cut -c1-90)"
done
echo SCAN_DONE
