#!/bin/sh
# confirmC: extra confirmation (NOT part of the rule): 512 further fresh seeds 26001-26512, 30 s, S6a and F1, once each
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
LOG=out/sprint6/confirmC.log
nice -n 10 .venv/bin/python scratchpad/sprint6/fr6.py params/run_gearz_v4_beyond_s6a.txt bin/challengers/run_gearz-s6-final 26001-26512 out/sprint6/confirmC_S6a.jsonl --workers 6 --tag "S6a CONFIRMATION C 26001-26512" >> $LOG 2>&1
nice -n 10 .venv/bin/python scratchpad/sprint6/fr6.py params/run_geary_v4_beyond_s5b.txt bin/challengers/run_geary-s5-final 26001-26512 out/sprint6/confirmC_F1.jsonl --workers 6 --tag "F1 CONFIRMATION C 26001-26512" >> $LOG 2>&1
echo "==> Done confirmC" >> $LOG
