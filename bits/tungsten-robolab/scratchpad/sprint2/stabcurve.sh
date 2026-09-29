#!/bin/sh
# stabcurve.sh PARAMS REF "limit1 limit2 ..."  value of an ideal trunk torque of a given limit (kp 2000, kd 100, fixed reference REF rad), 4 flying seeds 12 s
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
. scratchpad/sprint2/env.sh
export ROBOLAB_SNAP=${ROBOLAB_SNAP:-run_v4_p95j}
P=$1; REF=$2; shift 2
for L in $1; do
  echo "== limit $L N m, ref $REF"
  ROBOLAB_TRUNK_STAB=2000,100,$L ROBOLAB_TRUNK_STAB_REF=$REF .venv/bin/python scratchpad/sprint2/lab.py $P --task sprint_touch_v4x --controller ${CTL:-bin/challengers/run_gear-v4c} --seeds ${SEEDS:-0,1,3,4} --seconds ${SECS:-12} --workers ${WORKERS:-2} 2>&1 | tail -1
done
