#!/bin/sh
# per-state ideals (board mode, cap 20 BW, init = the one-start ideal, 100k evals each, 6 workers): how much headroom does adapting the program to ONE state have? L3
cd /Users/erik/tungsten/bits/tungsten-robolab
while [ ! -f out/lj3/rob_r3.done ]; do sleep 5; done
for st in r1_s8088 r1_s8062 r1_s8099 r1_s8038 r1_s8078 r1_s8056; do
  echo "run $st" >> out/lj3/perstate.index
  scratchpad/lj3/optb.sh $st ps 151.025 100000 0.03 200 out/long_jump_limits/bs45_b20.json --grfcap 20 --grfw 0.3 --lmin -15
done
echo done > out/lj3/perstate.done
