#!/bin/sh
# m1.sh -- M1 baselines (agent S6): F1 and the entered champion of the old trial on the 1000 SELECTION seeds 24001-25000 (30 s, labelled beyond-human body, fr.py of S5),
# preceded by a harness check of F1 on the 128 headline seeds 12001-12128 against the arena's recorded per-seed scores of the champion of sprint_top_speed_v4_beyond_fresh128.
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
W=${WORKERS:-6}
F1C=bin/challengers/run_geary-s5-final; F1P=params/run_geary_v4_beyond_s5b.txt
CC=bin/challengers/run_gearx-s4a; CP=params/run_gearx_v4_beyond_c.txt
nice -n 10 .venv/bin/python scratchpad/sprint5/fr.py $F1P $F1C 12001-12128 out/sprint6/m1_F1_head_check.jsonl --workers $W --tag "F1 harness check 12001-12128" >> out/sprint6/m1.log 2>&1
nice -n 10 .venv/bin/python scratchpad/sprint5/fr.py $F1P $F1C 24001-25000 out/sprint6/m1_F1_sel.jsonl --workers $W --tag "F1 SELECTION 24001-25000" >> out/sprint6/m1.log 2>&1
nice -n 10 .venv/bin/python scratchpad/sprint5/fr.py $CP $CC 24001-25000 out/sprint6/m1_champC_sel.jsonl --workers $W --tag "entered champion of the old trial (S4 chain C) SELECTION 24001-25000" >> out/sprint6/m1.log 2>&1
echo "==> Done m1" >> out/sprint6/m1.log
