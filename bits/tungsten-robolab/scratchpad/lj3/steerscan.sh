#!/bin/sh
# capture seeds 8001-8048 for each steering setting SA1..SA5 (4 procs each, one after the other) and summarise the penultimate gap. L3
cd /Users/erik/tungsten/bits/tungsten-robolab
while [ ! -f out/lj3/scan3.done ]; do sleep 5; done
for k in 1 2 3 4 5; do
  scratchpad/lj3/capset.sh scratchpad/lj3/SA$k.txt sa$k bin/challengers/long_jump_run_x-l3b 8001 8048 4
  .venv/bin/python scratchpad/lj3/gapscan2.py sa$k 8001 8048 2.83 0.15 --quiet >> out/lj3/steerscan.txt 2>&1
done
echo done > out/lj3/steerscan.done
