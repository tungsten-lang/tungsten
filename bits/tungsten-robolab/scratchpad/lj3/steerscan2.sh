#!/bin/sh
cd /Users/erik/tungsten/bits/tungsten-robolab
for k in 1 2; do
  scratchpad/lj3/capset.sh scratchpad/lj3/SD$k.txt sd$k bin/challengers/long_jump_run_x-l3b 8001 8128 2
  .venv/bin/python scratchpad/lj3/gapscan2.py sd$k 8001 8128 2.83 0.15 --quiet >> out/lj3/steerscan2.txt 2>&1
done
echo done > out/lj3/steerscan2.done
