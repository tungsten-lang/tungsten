#!/bin/sh
# scan6.sh NAME PARAMS CTL SEEDS SECS "k=v,k=v" "k=v" ...   (the first set may be "" = the baseline)
# one fr6.py run per parameter override set (labelled beyond-human body, standing starts); the 2-line summary of each is appended to out/sprint6/scan_NAME.log,
# the per-seed rows go to out/sprint6/scan_NAME_<i>.jsonl.   WORKERS (default 6); ATTR = extra "--attr k=v,..." value
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
NAME=$1; P=$2; C=$3; SEEDS=$4; SECS=$5; shift 5
i=0
for S in "$@"; do
  i=$((i+1))
  nice -n 10 .venv/bin/python scratchpad/sprint6/fr6.py $P $C $SEEDS out/sprint6/scan_${NAME}_$i.jsonl --seconds $SECS --workers ${WORKERS:-6} --set "$S" --tag "[$S]" 2>&1 | head -2 >> out/sprint6/scan_$NAME.log
done
echo "==> Done scan $NAME" >> out/sprint6/scan_$NAME.log
