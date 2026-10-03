#!/bin/sh
# es5.sh ARM SEARCH_SEED BUDGET [WORKERS] [INIT] [SNAP_TRAIN] [TAG]   the anat5 A/B search: (1+16)-ES, --agg ${AGG:-mean} (mean: a candidate dies at its first fall; meanall: falls do not stop it, for a failing start), on the gear-5 twins of the P95 five-gear champion,
# 8 flying-start seeds x 16 s, objective 3 (pace), fall penalty 300, sigma 0.03; ARM v4 (control, playground/calibrations/v4.json) or v5 (v5.json).
# Outputs scratchpad/anat5/es_<ARM>_s<SEED><TAG>.{txt,log,jsonl,npz,pid}. The swing-recovery tunables are IN the search (drv_swh widened to 0:1, drv_swk 0:1,
# heel_tuck 0:0.8, k_fo, k_mid, k_late 0.3:3, psi_fo/mid/late, knee_lift, t_flight, stiff_sw, drv_rf, drv_hamb, drv_pre, k_clear, clear_h); k_syn, t_swing and the other
# gait-1/gait-2 only tunables are dead in the six-chunk stride (verified: scratchpad/anat5/LOG.md) and start-phase tunables do not matter from a flying start.
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
ARM=$1; SS=$2; BUDGET=$3; WORKERS=${4:-3}; INIT=${5:-scratchpad/anat5/params/x5a_fly.txt}; SNAP=${6:-run_${ARM}_a5t}; TAG=${7:-}
. scratchpad/anat5/env_$ARM.sh
export RUN_NATURAL_START=flying
export ROBOLAB_SNAP=$SNAP
export ROBOLAB_CONTROLLER=${ROBOLAB_CONTROLLER:-bin/challengers/run_gearx-a}
G=${GEAR:-5}
NAME=es_${ARM}_g${G}_s${SS}${TAG}
EXCL="g${G}_v0,g${G}_accel,g${G}_d_go,g${G}_drv0_knee,g${G}_drv0_ankle,g${G}_drv0_hip,g${G}_psi0,g${G}_k0,g${G}_t0_max,g${G}_v_tau,g${G}_lean_acc,g${G}_drv_floor,g${G}_drv_knee,g${G}_drv_ankle,g${G}_drv_gas,g${G}_drv_ham,g${G}_drv_hip,g${G}_psi_drive,g${G}_k_drive,g${G}_t_drive,g${G}_t_soft,g${G}_t_stance,g${G}_t_swing,g${G}_t_kext,g${G}_t_kdur,g${G}_t_step_min,g${G}_k_syn,g${G}_k_trail"
BOX="g${G}_z_ref=0.6:1.0,g${G}_k_land=-0.2:0.9,g${G}_t_push_max=0.03:0.3,g${G}_a_push=0.2:1.3,g${G}_k_late=0.3:3.0,g${G}_g_kl=0.1:2.5,g${G}_hip_lead=0:0.3,g${G}_vz_push=-0.8:0.4,g${G}_k_fly=0:3,g${G}_elbow=0.3:3.0,g${G}_psi_to=-1.0:0.2,g${G}_k_push=0:0.8,g${G}_psi_reach=-0.3:0.9,g${G}_k_reach=0:0.9"
BOX="$BOX,g${G}_t_land=0.002:0.25,g${G}_a_reach=-0.6:0.6,g${G}_fall_ankle=-0.3:0.4,g${G}_gait_spring=0.002:0.2"
BOX="$BOX,g${G}_drv_swh=0:1.0,g${G}_drv_swk=0:1.0,g${G}_v_cap=2.5:12,g${G}_v_top=2.5:12,g${G}_torso_kd=0.05:0.8,g${G}_toe_push=-0.8:0.8"
[ -n "$EXTRA_BOX" ] && BOX="$BOX,$EXTRA_BOX"
EXCL_EXTRA=${EXCL_EXTRA:+,$EXCL_EXTRA}
SEEDS=${SEEDS:-0,1,2,3,4,5,6,7}
nohup nice -n 10 .venv/bin/python -u playground/hsearch.py sprint_touch_v4x --method es --agg ${AGG:-mean} --lam 16 --seed $SS --budget $BUDGET --workers $WORKERS --sigma ${SIGMA:-0.03} --seconds 16 \
  --seeds $SEEDS --attrs "objective=3,fly_touch=2,fall_pen=300" --init $INIT --only "g${G}_*" --exclude "$EXCL$EXCL_EXTRA" --box "$BOX" \
  --out scratchpad/anat5/$NAME.txt --log scratchpad/anat5/$NAME.jsonl --archive scratchpad/anat5/$NAME.npz > scratchpad/anat5/$NAME.log 2>&1 &
echo $! > scratchpad/anat5/$NAME.pid
echo "started $NAME pid $(cat scratchpad/anat5/$NAME.pid) (arm $ARM, search seed $SS, budget $BUDGET, workers $WORKERS, snap $SNAP, init $INIT)"
