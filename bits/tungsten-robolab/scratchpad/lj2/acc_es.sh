#!/bin/sh
# acceleration-gear ES (L2): the middle gear of scratchpad/lj2/acc0.txt (gears 3: g2 = searched from gear 1's values, switch 3.5 m/s;
# g3 = the frozen runner's cruise gear from 5.0 m/s), objective = the distance a standing start covers in 9.6 s (min over 6 starts, falls penalised),
# approach only (j_run 1) on a 60 m runway so the board is never reached. usage: acc_es.sh <tag> <budget> [init]
cd /Users/erik/tungsten/bits/tungsten-robolab
TAG=${1:-es1}; BUDGET=${2:-1000}; INIT=${3:-scratchpad/lj2/acc0.txt}
export ROBOLAB_CALIB=v4 ROBOLAB_PROFILE=p95 ROBOLAB_PROFILE_PARTS=strength,speed,tendon,activation ROBOLAB_LJ_APPROACH=60 ROBOLAB_CONTROLLER=bin/challengers/long_jump_run-c2
.venv/bin/python playground/hsearch.py long_jump_v4_p95b --method es --budget $BUDGET --workers 2 --sigma 0.03 --seconds 9.6 \
  --seeds 5001,5002,5003,5004,5005,5006 --init $INIT --only 'g2_*' \
  --exclude 'g2_v_on,g2_v0,g2_accel,g2_d_go,g2_drv0_*,g2_psi0,g2_k0,g2_t0_max,g2_lean_acc,g2_v_tau,g2_drv_floor,g2_j_*' \
  --out scratchpad/lj2/acc_$TAG.txt --log scratchpad/lj2/acc_$TAG.jsonl --archive scratchpad/lj2/acc_$TAG.npz
echo done > scratchpad/lj2/acc_$TAG.done
