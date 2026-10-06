#!/bin/sh
# final_all.sh: the final protocol of S6 (see LOG): selection run, identity run, arena-seed run, TEST A/B for S6a and F1
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
W=6
S6P=params/run_gearz_v4_beyond_s6a.txt; S6C=bin/challengers/run_gearz-s6-final
F1P=params/run_geary_v4_beyond_s5b.txt
LOG=out/sprint6/final_all.log
nice -n 10 .venv/bin/python scratchpad/sprint6/fr6.py $S6P $S6C 24001-25000 out/sprint6/final_S6a_sel.jsonl --workers $W --tag "S6a SELECTION 24001-25000" >> $LOG 2>&1
nice -n 10 .venv/bin/python scratchpad/sprint6/fr6.py $F1P $S6C 12001-12128 out/sprint6/final_id_F1_via_gearz.jsonl --workers $W --tag "F1 params through run_gearz-s6-final, arena seeds 12001-12128 (identity)" >> $LOG 2>&1
nice -n 10 .venv/bin/python scratchpad/sprint6/fr6.py $S6P $S6C 12001-12128 out/sprint6/final_S6a_arena128.jsonl --workers $W --tag "S6a arena seeds 12001-12128" >> $LOG 2>&1
scratchpad/sprint6/final6.sh $S6P $S6C S6a $W
scratchpad/sprint6/final6.sh $F1P bin/challengers/run_geary-s5-final F1 $W
echo "==> Done final_all" >> $LOG
