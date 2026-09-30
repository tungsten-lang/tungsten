#!/bin/sh
# ceil.sh LABEL PROFILE_PATH V0 VMAX WORKERS INIT SEED -- the ideal-control ceiling chain of a body (same recipe as the sprinter's sparse chain: 1 m/s spacing, --cycle 0, --stop budget).
# Output out/sprint_limits/probe_LABEL_v*_k*_speeds.json, log scratchpad/sprint4/LABEL.log, pid scratchpad/sprint4/LABEL.pid. Read it with scratchpad/sprint_knot/budget_ceiling.py <LABEL without _sN>.
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
L=$1; P=$2; V0=$3; VMAX=$4; W=$5; INIT=$6; SEED=${7:-1}
ROBOLAB_BODY=v4 ROBOLAB_CALIB=v4 ROBOLAB_CALIB_SET= nohup .venv/bin/python -u scratchpad/sprint_knot/ceiling_probe.py $L --profile $P --v0 $V0 --dv 1.0 --seed $SEED --vmax $VMAX --workers $W --cycle 0 --stop budget --init $INIT > scratchpad/sprint4/$L.log 2>&1 &
echo $! > scratchpad/sprint4/$L.pid
echo "started $L pid $(cat scratchpad/sprint4/$L.pid)"
