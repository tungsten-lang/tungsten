#!/bin/sh
# mech.sh PARAMS "set1" "set2" ...   lab rows (4 flying seeds, 12 s, 2 workers) for parameter sets given as k=v,k=v with the gearx binary.
# env: SEEDS (default 0,1,3,4), SECS (12), ROBOLAB_SNAP (run_v4_p95j), CTL (bin/challengers/run_gearx-a), TASKNAME (sprint_touch_v4x)
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
. scratchpad/sprint2/env.sh
export ROBOLAB_SNAP=${ROBOLAB_SNAP:-run_v4_p95j}
P=$1; shift
for s in "$@"; do
  echo "== $s"
  .venv/bin/python scratchpad/sprint2/lab.py $P --task ${TASKNAME:-sprint_touch_v4x} --controller ${CTL:-bin/challengers/run_gearx-a} --seeds ${SEEDS:-0,1,3,4} --seconds ${SECS:-12} --workers ${WORKERS:-2} --set "$s" 2>&1 | tail -6 | cut -c1-230
done
