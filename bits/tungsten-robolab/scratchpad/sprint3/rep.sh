#!/bin/sh
# rep.sh PARAMS CTL SEEDLIST [SECS] [WORKERS]  -- standing-start replay on the SPRINTER body (env.sh): one line per seed
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
. scratchpad/sprint3/env.sh
.venv/bin/python scratchpad/sprint_touch/probe.py run_v4 $1 --seconds ${4:-30} --seeds $3 --workers ${5:-2} --controller $2 2>&1 | python3 -c "
import sys, json, statistics
rows=[]
for l in sys.stdin:
    try: d=json.loads(l)
    except Exception: print(l[:200]); continue
    rows.append(d)
for d in rows:
    print('seed %s %s t %.1f peak %.3f steady %.3f contact %.3f flight %.3f stepf %.2f steplen %.2f grf %.2f pitch %.2f' % (d.get('seed'), 'FELL' if d.get('fell') else 'ok  ', d.get('time') or 0, d.get('peak_speed_1s') or 0, d.get('steady_speed') or 0, d.get('contact_time') or 0, d.get('flight_time') or 0, d.get('step_freq') or 0, d.get('step_length') or 0, d.get('peak_grf') or 0, d.get('torso_pitch') or 0))
falls=[(r.get('seed'), r.get('time')) for r in rows if r.get('fell')]
ok=[r.get('peak_speed_1s') for r in rows if not r.get('fell') and r.get('peak_speed_1s')]
print('falls %d/%d' % (len(falls), len(rows)), falls)
if ok: print('survivors peak mean %.3f min %.3f max %.3f' % (statistics.mean(ok), min(ok), max(ok)))
"
