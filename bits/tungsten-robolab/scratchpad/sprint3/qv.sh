#!/bin/sh
# qv.sh "k=v,k=v" SEEDS SECS [PARAMS] [CTL] [WORKERS]  -- standing-start probe on the SPRINTER body with parameter overrides (probe.py --set)
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
. scratchpad/sprint3/env.sh
P=${4:-params/run_gearx_v4_p95_x5a.txt}; C=${5:-bin/challengers/run_gearx-a}
.venv/bin/python scratchpad/sprint_touch/probe.py run_v4 $P --seconds $3 --seeds $2 --workers ${6:-2} --controller $C --set "$1" 2>&1 | python3 -c "
import sys, json, statistics
rows=[]
for l in sys.stdin:
    try: rows.append(json.loads(l))
    except Exception: print(l[:200])
line=[]
for d in rows:
    line.append('%s:%s%.2f/%.1f' % (d.get('seed'), 'F' if d.get('fell') else '', d.get('peak_speed_1s') or 0, d.get('time') or 0))
print('$1 |', ' '.join(line))
falls=[r for r in rows if r.get('fell')]
ok=[r.get('peak_speed_1s') for r in rows if not r.get('fell') and r.get('peak_speed_1s')]
print('  falls %d/%d' % (len(falls), len(rows)), ('survivors peak mean %.3f min %.3f' % (statistics.mean(ok), min(ok))) if ok else '')
"
