#!/bin/sh
# probe_batch.sh: run ceiling probes sequentially; each line of $1: label|profile|calib_set|v0
cd /Users/erik/tungsten/bits/tungsten-robolab
while IFS='|' read -r label prof cset v0; do
  [ -z "$label" ] && continue
  case "$label" in \#*) continue;; esac
  for seed in ${SEEDS:-1 2}; do
    P=""; [ -n "$prof" ] && P="--profile $prof"
    ROBOLAB_BODY=v4 ROBOLAB_CALIB="${CALIB:-}" ROBOLAB_CALIB_SET="$cset" .venv/bin/python scratchpad/sprint_knot/ceiling_probe.py "${label}_s$seed" $P --v0 "${v0:-5.0}" --seed $seed ${PROBE_ARGS:-} 2>&1 | tail -1
  done
done < "$1"
echo "BATCH DONE"
