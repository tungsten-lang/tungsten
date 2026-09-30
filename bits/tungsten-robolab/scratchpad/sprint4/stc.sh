#!/bin/sh
# stc.sh NAME INIT SEEDS BUDGET WORKERS [SIGMA] [SECONDS] -- JOINT ES on the gear-1 tunables AND the gear-2 twins from STANDING starts on the BEYOND-HUMAN body (the start, the acceleration and the gear-1 -> gear-2 handover
# with the handover speed g2_v_on fixed in INIT; gears 3+ excluded). AGG (default meanall) LAM (default 12). Outputs scratchpad/sprint4/NAME.{log,txt,jsonl,npz,pid}.
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
. scratchpad/sprint4/env.sh
NAME=$1; INIT=$2; SEEDS=$3; BUDGET=$4; WORKERS=$5; SIGMA=${6:-0.03}; SECS=${7:-14}
export RUN_NATURAL_START=standing
export ROBOLAB_CONTROLLER=${ROBOLAB_CONTROLLER:-bin/challengers/run_gearx-a}
export HSEARCH_UB=${HSEARCH_UB:-400}
EXCL="g3_*,g4_*,g5_*,g6_*,g7_*,g8_*,v_top,v_cap,k_sp,k_spd,fall_lean,fall_ankle,fall_place,g2_v_top,g2_v_cap,g2_v0,g2_accel,g2_d_go,g2_drv0_knee,g2_drv0_ankle,g2_drv0_hip,g2_psi0,g2_k0,g2_t0_max,g2_v_tau,g2_lean_acc,g2_psi_drive,g2_k_drive,g2_t_drive,g2_t_soft,g2_t_stance,g2_t_swing,g2_t_kext,g2_t_kdur,g2_t_step_min,g2_k_syn,g2_k_trail${EXCL_EXTRA:+,$EXCL_EXTRA}"
BOX="psi_ms=-0.6:0.5,vz_push=-0.8:0.4,k_fly=0:3,g_kl=0.1:2.5,drv_hip=0:1.0,drv_swh=0:1.0,lean=-0.2:0.4,g2_psi_ms=-0.6:0.5,g2_vz_push=-0.8:0.4,g2_k_fly=0:3,g2_g_kl=0.1:2.5,g2_drv_hip=0:1.0,g2_drv_swh=0:1.0,g2_lean=-0.2:0.4${EXTRA_BOX:+,$EXTRA_BOX}"
nohup .venv/bin/python -u playground/hsearch.py sprint_touch_v4x --method es --agg ${AGG:-meanall} --lam ${LAM:-12} --budget $BUDGET --workers $WORKERS --sigma $SIGMA --seconds $SECS \
  --seeds $SEEDS --attrs "${ATTRS:-objective=3,fall_pen=300}" --init $INIT --exclude "$EXCL" --box "$BOX" \
  --out scratchpad/sprint4/$NAME.txt --log scratchpad/sprint4/$NAME.jsonl --archive scratchpad/sprint4/$NAME.npz > scratchpad/sprint4/$NAME.log 2>&1 &
echo $! > scratchpad/sprint4/$NAME.pid
echo "started $NAME pid $(cat scratchpad/sprint4/$NAME.pid)"
