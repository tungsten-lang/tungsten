#!/bin/sh
# every <secs> s: copy the current snapshot of a robust stage and evaluate it in the harness on the held-out list (and the training list). usage: monitor.sh <tag> <train-list> <held-list> <secs> <n>
cd /Users/erik/tungsten/bits/tungsten-robolab
tag=$1; tr=$2; he=$3; secs=$4; n=$5
i=0
while [ $i -lt $n ]; do
  sleep $secs
  i=$(( i + 1 ))
  [ -f out/lj4/rob_${tag}.txt ] || continue
  cp out/lj4/rob_${tag}.txt out/lj4/rob_${tag}_snap$i.txt
  g=$(grep -E "^gen" out/lj4/rob_${tag}.log | tail -1 | cut -c1-60)
  h=$(scratchpad/lj4/snapeval.sh out/lj4/rob_${tag}_snap$i.txt $he 1.5)
  t=$(scratchpad/lj4/snapeval.sh out/lj4/rob_${tag}_snap$i.txt $tr 1.5)
  echo "snap$i [$g] HELD: $h | TRAIN: $t" >> out/lj4/rob_${tag}.monitor.txt
  [ -f out/lj4/rob_${tag}.done ] && break
done
