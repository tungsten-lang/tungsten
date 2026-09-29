#!/bin/sh
# standval.sh PARAMS CTL LO HI [WORKERS]  standing-start 30 s validation on seeds LO..HI (run_v4, the arena's task): falls and per-start peaks
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
. scratchpad/sprint2/env.sh
SEEDS=$(python3 -c "print(','.join(str(i) for i in range($3, $4+1)))")
.venv/bin/python scratchpad/sprint_touch/probe.py run_v4 $1 --seconds 30 --seeds $SEEDS --workers ${5:-3} --controller $2 2>&1 | python3 -c "
import sys, json, statistics
rows=[]
for l in sys.stdin:
    try: d=json.loads(l)
    except Exception: print(l[:160]); continue
    rows.append((d.get('seed'), bool(d.get('fell')), d.get('time'), d.get('peak_speed_1s'), d.get('steady_speed')))
falls=[(r[0], r[2]) for r in rows if r[1]]
ok=[r[3] for r in rows if not r[1] and r[3]]
print('seeds $3-$4: falls %d/%d' % (len(falls), len(rows)), falls)
if ok: print('  peak mean %.3f min %.3f max %.3f' % (statistics.mean(ok), min(ok), max(ok)))
"
