#!/bin/sh
# scan3.sh BASE_PARAMS SNAP NSEEDS SECS "set1" "set2" ...   -- one lab.py flying-start probe per --set string; prints falls / mean fall time / mean peak of all
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
. scratchpad/sprint4/env.sh
BASE=$1; export ROBOLAB_SNAP=$2; N=$3; SECS=$4; shift 4
SEEDS=$(python3 -c "print(','.join(str(i) for i in range($N)))")
for S in "$@"; do
  .venv/bin/python scratchpad/sprint2/lab.py $BASE --task sprint_touch_v4x --controller ${CTL:-bin/challengers/run_gearx-a} --seeds $SEEDS --seconds $SECS --workers ${WORKERS:-2} --set "$S" 2>&1 | python3 -c "
import sys, re
rows=[]
for l in sys.stdin:
    m=re.match(r'\s*(\d+)\s+(FALL|ok)\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)', l)
    if m: rows.append((int(m.group(1)), m.group(2)=='FALL', float(m.group(3)), float(m.group(4)), float(m.group(5))))
n=len(rows); f=sum(1 for r in rows if r[1])
mt=sum(r[2] for r in rows)/max(n,1); mp=sum(r[3] for r in rows)/max(n,1)
st=[r[4] for r in rows if not r[1] and r[4]>0]
print('%-40s falls %d/%d  mean t %.1f  mean peak %.3f  survivors steady %s' % ('$S', f, n, mt, mp, ('%.3f (n=%d)' % (sum(st)/len(st), len(st))) if st else '-'), flush=True)
"
done
