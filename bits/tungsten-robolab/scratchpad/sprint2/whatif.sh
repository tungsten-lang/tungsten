#!/bin/sh
# whatif.sh PARAMS F "m1 m2 ..."  the same controller on P95 bodies whose single muscle group m is F x stronger (diagnostic), 4 flying seeds 12 s
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
. scratchpad/sprint2/env.sh
export ROBOLAB_SNAP=${ROBOLAB_SNAP:-run_v4_p95j}
P=$1; F=$2; shift 2
for M in $1; do
  echo "== $M x$F"
  ROBOLAB_PROFILE=scratchpad/sprint2/profiles/p95_${M}_${F}.json .venv/bin/python scratchpad/sprint2/lab.py $P --task sprint_touch_v4x --controller ${CTL:-bin/challengers/run_gear-v4c} --seeds ${SEEDS:-0,1,3,4} --seconds ${SECS:-12} --workers ${WORKERS:-2} 2>&1 | tail -1
done
