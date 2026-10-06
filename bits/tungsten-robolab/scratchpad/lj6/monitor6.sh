#!/bin/sh
# L6: every <secs> seconds snapshot a training run's program and evaluate it in the harness on a held-out list (single process, nice): tail counts beside the clipped mean.
# usage: monitor6.sh <tag> <held-list-file> <secs> <n> [extra ljx_risk --eval args, e.g. --shift 0.1]
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
. scratchpad/lj6/env6.sh
export ROBOLAB_LJ_APPROACH=151.025 ROBOLAB_LJ_MARGIN=0.03
tag=$1; he=$2; secs=$3; n=$4; shift 4
i=0
while [ $i -lt $n ]; do
  sleep $secs
  i=$(( i + 1 ))
  [ -f out/lj6/rk_${tag}.txt ] || continue
  cp out/lj6/rk_${tag}.txt out/lj6/rk_${tag}_snap$i.txt
  g=$(grep -E "^gen [0-9]+ sims" out/lj6/rk_${tag}.log | tail -1 | cut -c1-70)
  o=$(nice -n 10 .venv/bin/python scratchpad/lj6/ljx_risk.py --eval out/lj6/rk_${tag}_snap$i.txt --captures "$(cat $he)" --fmin 1.5 --workers 1 --lmax -1.0 --lw 1.0 --pw 3.5 --quiet "$@" 2>&1 | grep -E "^TAIL")
  echo "snap$i [$g] HELD: $o" >> out/lj6/rk_${tag}.monitor.txt
  [ -f out/lj6/rk_${tag}.done ] && break
done
