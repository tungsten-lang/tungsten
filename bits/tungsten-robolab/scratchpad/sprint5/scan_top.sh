#!/bin/sh
# scan_top.sh NAME PARAMS CTL SNAP SECS "k=v,k=v" ...  -- TOP-gear lever scan from the flying snapshot set SNAP (seeds = state indices 0..N-1, N from SEEDS env, default 0-222)
# the params file must carry gear0 2 + fly_entry 2 (D_top_fly.txt); results out/sprint5/scan_NAME*.jsonl / .log, read with scanres.py
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
NAME=$1; P=$2; C=$3; SNAP=$4; SECS=$5; shift 5
i=0
for S in "$@"; do
  i=$((i+1))
  nice -n 10 .venv/bin/python scratchpad/sprint5/fr.py $P $C ${SEEDS:-0-222} out/sprint5/scan_${NAME}_$i.jsonl --seconds $SECS --workers ${WORKERS:-2} --task ${TASK:-sprint_touch_v4x} --start flying --snap $SNAP --attr ${ATTR:-fly_touch=2,objective=3} --set "$S" --tag "[$S]" 2>&1 | head -2 >> out/sprint5/scan_$NAME.log
done
echo "==> Done scan $NAME" >> out/sprint5/scan_$NAME.log
