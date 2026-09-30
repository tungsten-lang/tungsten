#!/bin/sh
# esk.sh NAME INIT SEEDS BUDGET WORKERS [SIGMA] [SECONDS] -- ES on the gear-G twins (G = $GEAR, default 2) from STANDING starts (default) or flying starts ($RUN_NATURAL_START=flying + $ROBOLAB_SNAP)
# on the BEYOND-HUMAN body. AGG (default meanall) LAM (default 16). Gears below G are fixed at INIT's values (freeze twins first), so a stage's rollout runs the whole chain up to gear G
# (INIT must have `gears G` and g<G>_v_on set). The stance drives are searched (the body is 2.4x stronger; S3's exclusion list left them out).
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
. scratchpad/sprint4/env.sh
NAME=$1; INIT=$2; SEEDS=$3; BUDGET=$4; WORKERS=$5; SIGMA=${6:-0.03}; SECS=${7:-12}
export RUN_NATURAL_START=${RUN_NATURAL_START:-standing}
export ROBOLAB_CONTROLLER=${ROBOLAB_CONTROLLER:-bin/challengers/run_gearx-a}
export HSEARCH_UB=${HSEARCH_UB:-350}
G=${GEAR:-2}
EXCL="g${G}_v0,g${G}_accel,g${G}_d_go,g${G}_drv0_knee,g${G}_drv0_ankle,g${G}_drv0_hip,g${G}_psi0,g${G}_k0,g${G}_t0_max,g${G}_v_tau,g${G}_lean_acc,g${G}_psi_drive,g${G}_k_drive,g${G}_t_drive,g${G}_t_soft,g${G}_t_stance,g${G}_t_swing,g${G}_t_kext,g${G}_t_kdur,g${G}_t_step_min,g${G}_k_syn,g${G}_k_trail"
BOX="g${G}_z_ref=0.6:1.0,g${G}_k_land=-0.2:0.9,g${G}_t_push_max=0.03:0.3,g${G}_a_push=0.2:1.3,g${G}_k_late=0.3:3.0,g${G}_g_kl=0.1:2.5,g${G}_hip_lead=0:0.3,g${G}_vz_push=-0.8:0.4,g${G}_k_fly=0:3,g${G}_elbow=0.3:3.0,g${G}_psi_to=-1.0:0.2,g${G}_k_push=0:0.8,g${G}_psi_reach=-0.3:0.9,g${G}_k_reach=0:0.9"
[ -n "$EXTRA_BOX" ] && BOX="$BOX,$EXTRA_BOX"
[ -n "$EXCL_EXTRA" ] && EXCL="$EXCL,$EXCL_EXTRA"
nohup .venv/bin/python -u playground/hsearch.py sprint_touch_v4x --method es --agg ${AGG:-meanall} --lam ${LAM:-16} --budget $BUDGET --workers $WORKERS --sigma $SIGMA --seconds $SECS \
  --seeds $SEEDS --attrs "${ATTRS:-objective=3,fall_pen=300}" --init $INIT --only "g${G}_*" --exclude "$EXCL" --box "$BOX" \
  --out scratchpad/sprint4/$NAME.txt --log scratchpad/sprint4/$NAME.jsonl --archive scratchpad/sprint4/$NAME.npz > scratchpad/sprint4/$NAME.log 2>&1 &
echo $! > scratchpad/sprint4/$NAME.pid
echo "started $NAME pid $(cat scratchpad/sprint4/$NAME.pid)"
