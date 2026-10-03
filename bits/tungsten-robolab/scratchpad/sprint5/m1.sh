#!/bin/sh
# M1 baseline: champion (frozen controller + frozen params), chain C (own files), chain D on the 128 HEADLINE seeds 12001-12128 (30 s, beyond body)
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
PY=.venv/bin/python
CH=bin/champions/sprint_top_speed_v4_beyond-20260929-233725
CP=playground/arena/params/sprint_top_speed_v4_beyond-20260929-233725.txt
nice -n 10 $PY scratchpad/sprint5/fr.py $CP $CH 12001-12128 out/sprint5/m1_champion_head.jsonl --workers 6 --tag "champion (frozen files) headline 12001-12128"
nice -n 10 $PY scratchpad/sprint5/fr.py params/run_gearx_v4_beyond_c.txt bin/challengers/run_gearx-s4a 12001-12128 out/sprint5/m1_C_head.jsonl --workers 6 --tag "chain C headline 12001-12128"
nice -n 10 $PY scratchpad/sprint5/fr.py params/run_gearx_v4_beyond_d.txt bin/challengers/run_gearx-s4b 12001-12128 out/sprint5/m1_D_head.jsonl --workers 6 --tag "chain D headline 12001-12128"
echo "==> Done M1"
