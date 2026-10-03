#!/bin/sh
# optimiser hyper-parameter scan on capture b0_nom: init x pop x sigma, 200k evals each, one at a time (6 workers). L3.
cd /Users/erik/tungsten/bits/tungsten-robolab
P95I=out/long_jump_limits/p95pn_s0_ideal.json
i=0
for init in "" "$P95I"; do
 for pop in 200 800; do
  for sig in 0.04 0.08; do
   i=$((i+1))
   tag=s$i
   echo "run $tag init=${init:-recorded} pop=$pop sigma=$sig" >> out/lj3/scan1.index
   scratchpad/lj3/opt2.sh b0_nom $tag 200000 6 $sig $pop $init
  done
 done
done
echo done > out/lj3/scan1.done
