#!/bin/sh
# after the landing search C2: candidates C2, C3, C1 on the extended SELECTION set 7001-7288 (labelled beyond-human body, unlimited run-up; controller long_jump_run_y-l4b). L4
cd /Users/erik/tungsten/bits/tungsten-robolab
while [ ! -f out/lj4/land_C2.done ]; do sleep 5; done
export CTL=bin/challengers/long_jump_run_y-l4b
rm -f out/lj4/evalS2_all.done
# C2 = A2 + R1 + land_C2
scratchpad/lj4/evalrob.sh C2 7001-7288 6 scratchpad/lj4/A2.txt out/lj4/R1.txt out/lj4/land_C2.txt > out/lj4/ev_C2_7001.txt 2>&1
# C3 = C2 + regime tails (the tails file goes after the landing table in the assembled params, as extra files)
.venv/bin/python scratchpad/lj2/assemble.py out/lj4/par_C3.txt scratchpad/lj4/A2.txt out/lj4/R1.txt out/lj4/land_C2.txt out/lj4/tails2.txt > /dev/null
nice -n 10 .venv/bin/python playground/long_jump_eval.py long_jump_v4_beyond --params out/lj4/par_C3.txt --controller $CTL --task long_jump_v4_beyond_a --seeds 7001-7288 --workers 6 --out out/lj4/ev_C3_7001-7288.json > out/lj4/ev_C3_7001.txt 2>&1
# C1 = A2 + r3 + land_B1
scratchpad/lj4/evalrob.sh C1 7001-7288 6 scratchpad/lj4/A2.txt out/lj3/rob_r3_snap.txt out/lj4/land_B1.txt > out/lj4/ev_C1b_7001.txt 2>&1
echo done > out/lj4/evalS2_all.done
