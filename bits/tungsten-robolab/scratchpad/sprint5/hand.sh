#!/bin/sh
# hand.sh NAME INIT SNAP WORKERS MARGIN [rses.py args...]  -- HANDOVER search: the gear-2 tunables of a chain from gear-1 flying snapshots (6.9-7.4 m/s, ROBOLAB_SNAP=SNAP) with the REAL switch at g2_v_on
# (INIT: the chain + fly_entry 2, no gear0: the rollout starts in gear 1 at the snapshot, switches to gear 2 at 7.6 m/s and to gear 3 at 9.4); 14 s horizon.
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
NAME=$1; INIT=$2; SNAP=$3; W=$4; M=$5; shift 5
G=2
EXCL="g${G}_v_on,g${G}_v0,g${G}_accel,g${G}_d_go,g${G}_drv0_knee,g${G}_drv0_ankle,g${G}_drv0_hip,g${G}_psi0,g${G}_k0,g${G}_t0_max,g${G}_v_tau,g${G}_lean_acc,g${G}_psi_drive,g${G}_k_drive,g${G}_t_drive,g${G}_t_soft,g${G}_t_stance,g${G}_t_swing,g${G}_t_kext,g${G}_t_kdur,g${G}_t_step_min,g${G}_k_syn,g${G}_k_trail"
BOX="g${G}_z_ref=0.6:1.0,g${G}_k_land=-0.2:0.9,g${G}_t_push_max=0.03:0.3,g${G}_a_push=0.2:1.3,g${G}_k_late=0.3:3.0,g${G}_g_kl=0.1:2.5,g${G}_hip_lead=0:0.3,g${G}_vz_push=-0.8:0.4,g${G}_k_fly=0:3,g${G}_elbow=0.3:3.0,g${G}_psi_to=-1.0:0.2,g${G}_k_push=0:0.8,g${G}_psi_reach=-0.3:0.9,g${G}_k_reach=0:0.9,g${G}_v_top=8:14,g${G}_v_cap=8:14,g${G}_lean=-0.4:0.4,g${G}_k_swh=0:6,g${G}_k_pp=-0.5:0.8,g${G}_k_pr=-0.03:0.03,g${G}_lean_vn=-0.1:0.1,g${G}_k_pi=-0.5:0.5,g${G}_psi_ms=-0.6:0.5,g${G}_drv_hip=0:1.0,g${G}_drv_swh=0:1.0"
nohup nice -n 10 .venv/bin/python -u scratchpad/sprint5/rses.py $NAME $INIT --controller ${CTL:-bin/challengers/run_geary-s5a} --only "g${G}_*" --exclude "$EXCL" --box "$BOX" --start flying --snap $SNAP \
  --pool ${POOL:-0-799} --k ${K:-48} --k2 ${K2:-64} --lam ${LAM:-10} --seconds ${SECS:-14} --attrs objective=3,fly_touch=2,fall_pen=300 --margin $M \
  --workers $W "$@" > out/sprint5/$NAME.out 2>&1 &
echo $! > out/sprint5/$NAME.pid
echo "started $NAME pid $(cat out/sprint5/$NAME.pid)"
