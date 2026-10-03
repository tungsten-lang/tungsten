#!/bin/sh
# after the landing search B1: candidate C1 on the selection set, then a bigger pool of training / held-out captures (F1 + SB2). L4
cd /Users/erik/tungsten/bits/tungsten-robolab
while [ ! -f out/lj4/land_B1.done ]; do sleep 5; done
scratchpad/lj4/evalrob.sh C1 7001-7096 6 scratchpad/lj4/A2.txt out/lj3/rob_r3_snap.txt out/lj4/land_B1.txt > out/lj4/ev_C1_7001.txt 2>&1
touch out/lj4/ev_C1.done
rm -f out/lj4/cap3.done
scratchpad/lj4/capset.sh scratchpad/lj4/A2.txt y2 bin/challengers/long_jump_run_y-l4a 8385 9100 6
.venv/bin/python scratchpad/lj3/gapscan2.py y2 8385 9100 2.83 0.15 --quiet >> out/lj4/cap3_summary.txt 2>&1
touch out/lj4/cap3.done
