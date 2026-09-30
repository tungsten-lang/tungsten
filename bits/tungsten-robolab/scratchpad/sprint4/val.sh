#!/bin/sh
# val3.sh PARAMS SNAP N SECS [CTL] [WORKERS]  flying-start validation on the BEYOND-HUMAN body of a gear-K practice file on a snapshot set (task sprint_touch_v4x)
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
. scratchpad/sprint4/env.sh
export ROBOLAB_SNAP=$2
N=$3; SECS=$4
SEEDS=$(python3 -c "print(','.join(str(i) for i in range($N)))")
.venv/bin/python scratchpad/sprint2/lab.py $1 --task sprint_touch_v4x --controller ${5:-bin/challengers/run_gearx-a} --seeds $SEEDS --seconds $SECS --workers ${6:-2}
