#!/bin/sh
# mksnap.sh PARAMS CTL NAME SEEDS [T0] [T1] [VMIN] [VMAX] [WORKERS]  -- snapshot set playground/cache/sprint_touch_run_v4_NAME.npz on the BEYOND-HUMAN body
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
. scratchpad/sprint4/env.sh
.venv/bin/python scratchpad/sprint4/snap3.py $1 $2 playground/cache/sprint_touch_run_v4_$3.npz --seeds $4 --secs ${10:-14} --t0 ${5:-8} --t1 ${6:-12} --vmin ${7:-7.4} --vmax ${8:-8.6} --workers ${9:-2}
