#!/bin/sh
# bodytry2.sh BODYSPEC 'k=v,k=v' NAME [BASEPARAMS] [SNAP] [SEEDS] [SECS]   BODYSPEC = a calibration name (v4, v5, v5b) ; overrides on BASEPARAMS ; summary line
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
BODY=$1; SETS=$2; NAME=$3; BASE=${4:-scratchpad/anat5/params/x5a_g3fly.txt}; SNAP=${5:-run_v4_a5w}; SEEDS=${6:-0-18}; SECS=${7:-16}
python3 - "$BASE" "$SETS" "scratchpad/anat5/params/try_$NAME.txt" <<'PY'
import sys
base, sets, out = sys.argv[1:4]
kv = dict(x.split("=") for x in sets.split(",") if x)
lines = [l.rstrip("\n") for l in open(base)]
keep = [l for l in lines if not (l.strip() and not l.startswith("#") and l.split()[0] in kv)]
keep += [f"{k} {v}" for k, v in kv.items()]
open(out, "w").write("\n".join(keep) + "\n")
PY
export ROBOLAB_BODY=v4 ROBOLAB_CALIB=$BODY ROBOLAB_PROFILE=p95 ROBOLAB_PROFILE_PARTS=strength,speed,tendon,activation
unset ROBOLAB_CALIB_SET
export RUN_NATURAL_START=flying ROBOLAB_SNAP=$SNAP
nice -n 10 .venv/bin/python -u scratchpad/anat5/gait_probe.py scratchpad/anat5/params/try_$NAME.txt ${CTL:-bin/challengers/run_gearx-a} $SEEDS $SECS --task sprint_touch_v4x --attrs objective=3,fly_touch=2,fall_pen=300 --t0 ${T0:-6} 2>&1 | python3 -c "
import sys, re, json
falls = []; ok = 0
for l in sys.stdin:
    m = re.match(r'seed (\d+): FELL at ([\d.]+)', l)
    if m: falls.append(float(m.group(2)))
    if l.startswith('seed') and ': ok' in l: ok += 1
    if l.startswith('AGG'): agg = l.strip()
a = json.loads(agg[4:])
print('$BODY $NAME [$SETS]: survive %d/%d falls %s | steady %.2f fold %s (max %s) gain100 %s heel_zpk %s heel_hip %s cadence %s swing_t %s t_pk %s' % (ok, ok + len(falls), sorted(falls)[:6], a.get('task_steady_speed', 0), round(a.get('fold', 0)), round(a.get('fold_max', 0)), round(a.get('gain100', 0)), round(a.get('heel_zpk', 0), 2), round(a.get('heel_hip', 0), 2), round(a.get('cadence', 0), 2), round(a.get('swing_t', 0), 3), round(a.get('t_pk', 0), 3)))
"
