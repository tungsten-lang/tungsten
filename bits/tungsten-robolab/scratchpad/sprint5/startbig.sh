#!/bin/sh
# startbig.sh NAME WORKERS CTL "file|set" ...  -- START hazard of gear-1 variants on 1000 seeds (14001-15000), 10 s; each item is "chainfile|k=v,k=v" (set may be empty); summary lines in out/sprint5/scan_NAME.log
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
NAME=$1; W=$2; CTL=$3; shift 3
i=0
for item in "$@"; do
  i=$((i+1)); F=${item%%|*}; S=${item#*|}
  nice -n 10 .venv/bin/python scratchpad/sprint5/fr.py $F $CTL 14001-15000 out/sprint5/scan_${NAME}_$i.jsonl --seconds 10 --workers $W --set "$S" --tag "[$(basename $F) $S]" 2>&1 | head -2 >> out/sprint5/scan_$NAME.log
done
echo "==> Done scan $NAME" >> out/sprint5/scan_$NAME.log
