#!/bin/sh
# bodytry.sh 'peaks-json' NAME [PARAMS] [SNAP] [SEEDS] [SECS]  what-if body through ROBOLAB_CALIB_SET (v4 + the given peaks), flying starts, one summary line
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
PK=$1; NAME=$2; PARAMS=${3:-scratchpad/anat5/params/x5a_fly.txt}; SNAP=${4:-run_v4_a5t}; SEEDS=${5:-0-11}; SECS=${6:-12}
export ROBOLAB_BODY=v4 ROBOLAB_CALIB=v4 ROBOLAB_PROFILE=p95 ROBOLAB_PROFILE_PARTS=strength,speed,tendon,activation
export ROBOLAB_CALIB_SET="peaks=$PK"
export RUN_NATURAL_START=flying ROBOLAB_SNAP=$SNAP
nice -n 10 .venv/bin/python -u scratchpad/anat5/gait_probe.py $PARAMS ${CTL:-bin/challengers/run_gearx-a} $SEEDS $SECS --task sprint_touch_v4x --attrs objective=3,fly_touch=2,fall_pen=300 --t0 6 2>&1 | python3 -c "
import sys, re, json
falls = []; ok = 0
for l in sys.stdin:
    m = re.match(r'seed (\d+): FELL at ([\d.]+)', l)
    if m: falls.append(float(m.group(2)))
    if l.startswith('seed') and ': ok' in l: ok += 1
    if l.startswith('AGG'): agg = l.strip()
a = json.loads(agg[4:])
print('$NAME $PK: survive %d/%d falls at %s | steady %.2f fold %s gain100 %s cadence %s swing_t %s' % (ok, ok + len(falls), sorted(falls), a.get('task_steady_speed', 0), round(a.get('fold', 0)), round(a.get('gain100', 0)), round(a.get('cadence', 0), 2), round(a.get('swing_t', 0), 3)))
"
