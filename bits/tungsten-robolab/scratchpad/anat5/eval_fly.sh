#!/bin/sh
# eval_fly.sh BODY PARAMS NAME [SNAP] [SEEDS] [SECONDS] [T0]  -- flying-start probe of a gear-5 practice file on a snapshot set (default: the body's UNSEEN a5u set, all 44 starts, 24 s, tail from 12 s)
# writes scratchpad/anat5/out/fly_<NAME>.{log,json}
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
BODY=$1; PARAMS=$2; NAME=$3; SNAP=${4:-run_${BODY}_a5u}; SEEDS=${5:-0-43}; SECS=${6:-24}; T0=${7:-12}
. scratchpad/anat5/env_$BODY.sh
export RUN_NATURAL_START=flying ROBOLAB_SNAP=$SNAP
nice -n 10 .venv/bin/python -u scratchpad/anat5/gait_probe.py $PARAMS ${CTL:-bin/challengers/run_gearx-a} $SEEDS $SECS --task sprint_touch_v4x --attrs objective=3,fly_touch=2,fall_pen=300 --t0 $T0 --out scratchpad/anat5/out/fly_$NAME.json > scratchpad/anat5/out/fly_$NAME.log 2>&1
tail -1 scratchpad/anat5/out/fly_$NAME.log
