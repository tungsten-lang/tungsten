#!/bin/sh
# FINAL phase (the candidate is fixed): (1) C7 on the two TEST sets, (2) C7 + regime tails (M3) on the same sets and on the selection set S3, (3) a FRESH confirmation on 400 never-used seeds
# 11001-11400 for C7 and for L3's stock champion (its own frozen controller / params / task). LABELLED BEYOND-HUMAN BODY, UNLIMITED RUN-UP. L4
cd /Users/erik/tungsten/bits/tungsten-robolab
while [ ! -f out/lj4/phase3a.done ]; do sleep 5; done
rm -f out/lj4/final_all.done
CTL=bin/challengers/long_jump_run_y-l4b
scratchpad/lj4/testeval.sh C7 params/long_jump_beyond_rob2.txt $CTL 6
.venv/bin/python scratchpad/lj2/assemble.py out/lj4/par_C7t.txt params/long_jump_beyond_rob2.txt out/lj4/tails3.txt > /dev/null
scratchpad/lj4/testeval.sh C7t out/lj4/par_C7t.txt $CTL 6
nice -n 10 .venv/bin/python playground/long_jump_eval.py long_jump_v4_beyond --params out/lj4/par_C7t.txt --controller $CTL --task long_jump_v4_beyond_a --seeds 7001-7480 --workers 6 --out out/lj4/ev_C7t_7001-7480.json > out/lj4/ev_C7t_7001.txt 2>&1
nice -n 10 .venv/bin/python playground/long_jump_eval.py long_jump_v4_beyond_robust96 --params params/long_jump_beyond_rob2.txt --controller $CTL --task long_jump_v4_beyond_a --seeds 11001-11400 --workers 6 --out out/lj4/conf_C7_11001.json > out/lj4/conf_C7_11001.txt 2>&1
nice -n 10 .venv/bin/python playground/long_jump_eval.py long_jump_v4_beyond_robust96 --params playground/arena/params/long_jump_v4_beyond_robust96-20260930-190409.txt --controller bin/champions/long_jump_v4_beyond_robust96-20260930-190409 --task long_jump_v4_beyond_a --seeds 11001-11400 --workers 6 --out out/lj4/conf_L3_11001.json > out/lj4/conf_L3_11001.txt 2>&1
echo done > out/lj4/final_all.done
