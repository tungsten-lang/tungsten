#!/bin/sh
# bodychain.sh 'peaks-json' NAME [PARAMS] [CONTROLLER] [SEEDS] [SECS]  standing-start chain on a what-if body (v4 + peaks through ROBOLAB_CALIB_SET), gait_probe summary
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
PK=$1; NAME=$2; PARAMS=${3:-params/run_gearx_v4_p95_x5a.txt}; CTL=${4:-bin/challengers/run_gearx-a}; SEEDS=${5:-221-232}; SECS=${6:-30}
export ROBOLAB_BODY=v4 ROBOLAB_CALIB=v4 ROBOLAB_PROFILE=p95 ROBOLAB_PROFILE_PARTS=strength,speed,tendon,activation
export ROBOLAB_CALIB_SET="peaks=$PK"
nice -n 10 .venv/bin/python -u scratchpad/anat5/gait_probe.py $PARAMS $CTL $SEEDS $SECS --t0 ${T0:-8} --out scratchpad/anat5/out/chain_$NAME.json 2>&1 | python3 -c "
import sys, re, json
falls = []; ok = 0
for l in sys.stdin:
    m = re.match(r'seed (\d+): FELL at ([\d.]+)', l)
    if m: falls.append(float(m.group(2)))
    if l.startswith('seed') and ': ok' in l: ok += 1
    if l.startswith('AGG'): agg = l.strip()
a = json.loads(agg[4:])
print('$NAME $PK: survive %d/%d falls at %s | peak1s %.3f steady %.2f fold %s gain100 %s heel_zpk %s cadence %s swing_t %s' % (ok, ok + len(falls), sorted(falls), a.get('peak_speed_1s', 0), a.get('task_steady_speed', 0), round(a.get('fold', 0)), round(a.get('gain100', 0)), round(a.get('heel_zpk', 0), 2), round(a.get('cadence', 0), 2), round(a.get('swing_t', 0), 3)))
"
