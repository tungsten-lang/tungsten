#!/bin/sh
# training captures with the chosen steering SB2 (A2): seeds 8001-8384, prefix y2. L4
cd /Users/erik/tungsten/bits/tungsten-robolab
rm -f out/lj4/cap2.done
scratchpad/lj4/capset.sh scratchpad/lj4/A2.txt y2 bin/challengers/long_jump_run_y-l4a 8001 8384 6
.venv/bin/python scratchpad/lj3/gapscan2.py y2 8001 8384 2.83 0.15 --quiet >> out/lj4/cap2_summary.txt 2>&1
echo done > out/lj4/cap2.done
