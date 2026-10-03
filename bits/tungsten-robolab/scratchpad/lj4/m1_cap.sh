#!/bin/sh
# M1: penultimate-touchdown captures of seeds 8001-8128 for F1 + L3's steering SB1 (prefix y1) and F1 + planner without steering (prefix y0); gap summaries. L4
cd /Users/erik/tungsten/bits/tungsten-robolab
rm -f out/lj4/m1_cap.done
scratchpad/lj4/capset.sh scratchpad/lj4/A1.txt y1 bin/challengers/long_jump_run_y-l4a 8001 8128 6
.venv/bin/python scratchpad/lj3/gapscan2.py y1 8001 8128 2.83 0.15 --quiet >> out/lj4/m1_summary.txt 2>&1
scratchpad/lj4/capset.sh scratchpad/lj4/A1n.txt y0 bin/challengers/long_jump_run_y-l4a 8001 8128 6
.venv/bin/python scratchpad/lj3/gapscan2.py y0 8001 8128 2.83 0.15 --quiet >> out/lj4/m1_summary.txt 2>&1
echo done > out/lj4/m1_cap.done
