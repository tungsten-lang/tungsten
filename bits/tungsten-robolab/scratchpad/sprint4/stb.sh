#!/bin/sh
# stb.sh NAME INIT SEEDS BUDGET WORKERS [AGG] [SIGMA] [SECONDS] -- ES on the GEAR-1 tunables (the start and the acceleration) from STANDING starts on the BEYOND-HUMAN body;
# every gear twin is excluded (freeze twins first: scratchpad/sprint4/freeze_twins.py). Resumable via --init. Outputs scratchpad/sprint4/NAME.{log,txt,jsonl,npz,pid}.
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
. scratchpad/sprint4/env.sh
NAME=$1; INIT=$2; SEEDS=$3; BUDGET=$4; WORKERS=$5; AGG=${6:-meanall}; SIGMA=${7:-0.05}; SECS=${8:-7}
export RUN_NATURAL_START=standing
export ROBOLAB_CONTROLLER=${ROBOLAB_CONTROLLER:-bin/challengers/run_gearx-a}
export HSEARCH_UB=${HSEARCH_UB:-300}
EXCL="g2_*,g3_*,g4_*,g5_*,g6_*,g7_*,g8_*,v_top,v_cap,k_sp,k_spd,fall_lean,fall_ankle,fall_place${EXCL_EXTRA:+,$EXCL_EXTRA}"
nohup .venv/bin/python -u playground/hsearch.py sprint_touch_v4x --method es --agg $AGG --lam ${LAM:-16} --budget $BUDGET --workers $WORKERS --sigma $SIGMA --seconds $SECS \
  --seeds $SEEDS --attrs "objective=3,fall_pen=300" --init $INIT --exclude "$EXCL" ${BOX:+--box "$BOX"} \
  --out scratchpad/sprint4/$NAME.txt --log scratchpad/sprint4/$NAME.jsonl --archive scratchpad/sprint4/$NAME.npz > scratchpad/sprint4/$NAME.log 2>&1 &
echo $! > scratchpad/sprint4/$NAME.pid
echo "started $NAME pid $(cat scratchpad/sprint4/$NAME.pid)"
