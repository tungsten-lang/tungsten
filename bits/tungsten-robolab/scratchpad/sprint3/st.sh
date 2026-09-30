#!/bin/sh
# st.sh NAME INIT SEEDS BUDGET WORKERS [AGG] [SIGMA] [SECONDS]  -- ES on the gear-1 START twins from STANDING starts (SPRINTER body), resumable via --init
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
. scratchpad/sprint3/env.sh
NAME=$1; INIT=$2; SEEDS=$3; BUDGET=$4; WORKERS=$5; AGG=${6:-mean}; SIGMA=${7:-0.05}; SECS=${8:-8}
export RUN_NATURAL_START=standing
export ROBOLAB_CONTROLLER=${ROBOLAB_CONTROLLER:-bin/challengers/run_gearx-s3a}
nohup .venv/bin/python -u playground/hsearch.py sprint_touch_v4x --method es --agg $AGG --lam ${LAM:-12} --budget $BUDGET --workers $WORKERS --sigma $SIGMA --seconds $SECS \
  --seeds $SEEDS --attrs "objective=3,fall_pen=300" --init $INIT --only "accel,d_go,drv0_knee,drv0_ankle,drv0_hip,psi0,k0,t0_max,v_tau,lean_acc,drv_floor,v0" \
  --out scratchpad/sprint3/$NAME.txt --log scratchpad/sprint3/$NAME.jsonl --archive scratchpad/sprint3/$NAME.npz > scratchpad/sprint3/$NAME.log 2>&1 &
echo $! > scratchpad/sprint3/$NAME.pid
echo "started $NAME pid $(cat scratchpad/sprint3/$NAME.pid)"
