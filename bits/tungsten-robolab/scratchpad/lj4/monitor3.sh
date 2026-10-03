#!/bin/sh
# like monitor2.sh, with the forward-risk take-off count (L > 0 or pitch > 0.8). usage: monitor3.sh <tag> <train-list> <held-list> <secs> <n>
cd /Users/erik/tungsten/bits/tungsten-robolab
. scratchpad/lj4/env.sh
export ROBOLAB_LJ_APPROACH=151.025 ROBOLAB_LJ_MARGIN=0.03
tag=$1; tr=$2; he=$3; secs=$4; n=$5
i=0
while [ $i -lt $n ]; do
  sleep $secs
  i=$(( i + 1 ))
  [ -f out/lj4/rob_${tag}.txt ] || continue
  cp out/lj4/rob_${tag}.txt out/lj4/rob_${tag}_snap$i.txt
  g=$(grep -E "^gen" out/lj4/rob_${tag}.log | tail -1 | cut -c1-60)
  o=$(nice -n 10 .venv/bin/python scratchpad/lj4/ljx_robust.py --eval out/lj4/rob_${tag}_snap$i.txt --captures "$(cat $he)" --fmin 1.5 2>&1 | tail -2)
  fr=$(echo "$o" | head -1)
  h=$(.venv/bin/python scratchpad/lj4/clip.py "$(echo "$o" | tail -1)")
  echo "snap$i [$g] HELD: $h | $fr" >> out/lj4/rob_${tag}.monitor.txt
  [ -f out/lj4/rob_${tag}.done ] && break
done
