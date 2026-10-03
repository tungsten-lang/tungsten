#!/bin/sh
# try.sh BODY BASEPARAMS "k=v,k=v" NAME [SNAP] [SEEDS] [SECS]   one-at-a-time lab probe: BASEPARAMS with keys overridden, flying starts, summary line only
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
BODY=$1; BASE=$2; SETS=$3; NAME=$4; SNAP=${5:-run_${BODY}_a5t}; SEEDS=${6:-0-7}; SECS=${7:-12}
python3 - "$BASE" "$SETS" "scratchpad/anat5/params/try_$NAME.txt" <<'PY'
import sys
base, sets, out = sys.argv[1:4]
kv = dict(x.split("=") for x in sets.split(",") if x)
lines = [l.rstrip("\n") for l in open(base)]
keep = [l for l in lines if not (l.strip() and not l.startswith("#") and l.split()[0] in kv)]
keep += [f"{k} {v}" for k, v in kv.items()]
open(out, "w").write("\n".join(keep) + "\n")
PY
. scratchpad/anat5/env_$BODY.sh
export RUN_NATURAL_START=flying ROBOLAB_SNAP=$SNAP
nice -n 10 .venv/bin/python -u scratchpad/anat5/gait_probe.py scratchpad/anat5/params/try_$NAME.txt ${CTL:-bin/challengers/run_gearx-a} $SEEDS $SECS --task sprint_touch_v4x --attrs objective=3,fly_touch=2,fall_pen=300 --t0 6 2>&1 | python3 -c "
import sys, re
falls = []; ok = 0
for l in sys.stdin:
    m = re.match(r'seed (\d+): FELL at ([\d.]+)', l)
    if m: falls.append(float(m.group(2)))
    if l.startswith('seed') and ': ok' in l: ok += 1
    if l.startswith('AGG'): agg = l.strip()
import json
a = json.loads(agg[4:])
print('$NAME [$SETS]: survive %d/%d falls at %s | steady %.2f fold %s gain100 %s cadence %s swing_t %s' % (ok, ok + len(falls), sorted(falls), a.get('task_steady_speed', 0), round(a.get('fold', 0)), round(a.get('gain100', 0)), round(a.get('cadence', 0), 2), round(a.get('swing_t', 0), 3)))
"
