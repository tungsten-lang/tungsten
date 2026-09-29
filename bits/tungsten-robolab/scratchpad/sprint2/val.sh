#!/bin/sh
# val.sh PARAMS [SNAP] [NSEEDS] [SECS]   flying-start validation of a gear-5 practice file on a snapshot set (default: the 40 UNSEEN p95k starts, 24 s)
# prints the per-seed table's summary line (falls, mean/min peak) and the mean stance columns of the survivors
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
. scratchpad/sprint2/env.sh
export ROBOLAB_SNAP=${2:-run_v4_p95k}
N=${3:-40}; SECS=${4:-24}
SEEDS=$(python3 -c "print(','.join(str(i) for i in range($N)))")
.venv/bin/python scratchpad/sprint2/lab.py $1 --task sprint_touch_v4x --controller ${CTL:-bin/challengers/run_gear-v4c} --seeds $SEEDS --seconds $SECS --workers ${WORKERS:-4} > ${OUT:-/dev/stdout}
