#!/bin/sh
# like monitor.sh, but prints the official-like clipped harness metric (legal fraction x legal mean). usage: monitor2.sh <tag> <train-list> <held-list> <secs> <n>
cd /Users/erik/tungsten/bits/tungsten-robolab
tag=$1; tr=$2; he=$3; secs=$4; n=$5
i=0
while [ $i -lt $n ]; do
  sleep $secs
  i=$(( i + 1 ))
  [ -f out/lj4/rob_${tag}.txt ] || continue
  cp out/lj4/rob_${tag}.txt out/lj4/rob_${tag}_snap$i.txt
  g=$(grep -E "^gen" out/lj4/rob_${tag}.log | tail -1 | cut -c1-60)
  h=$(.venv/bin/python scratchpad/lj4/clip.py "$(scratchpad/lj4/snapeval.sh out/lj4/rob_${tag}_snap$i.txt $he 1.5)")
  t=$(.venv/bin/python scratchpad/lj4/clip.py "$(scratchpad/lj4/snapeval.sh out/lj4/rob_${tag}_snap$i.txt $tr 1.5)")
  echo "snap$i [$g] HELD: $h | TRAIN: $t" >> out/lj4/rob_${tag}.monitor.txt
  [ -f out/lj4/rob_${tag}.done ] && break
done
