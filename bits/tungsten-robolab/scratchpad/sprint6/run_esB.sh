#!/bin/sh
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
exec nice -n 10 .venv/bin/python scratchpad/sprint6/rses6.py esB scratchpad/sprint6/es_b.txt --ctl bin/challengers/run_gearz-s6g --train out/sprint6/deep_train.txt --valid out/sprint6/deep_valid.txt \
  --only "rk_st_*,rk_ln_*,rk_sr_*,rk_d_go,rk_psi0,rk_k0,rk_drv0_hip,rk_drv0_ankle,rk_drv0_knee,rk_t0_max,rk_stiff,rk_spine,rk_arm,rk_elbow,rk_k_bal,rk_lean,rk_lean_acc,rk_accel" \
  --exclude "rk_thr,rk_cap_st,rk_cap_ln,rk_rate_st,rk_rate_ln" --seconds 4.5 --k 120 --k2 100 --lam 6 --sigma 0.06 --mut 4 --vref 3.0 --vw 0.3 --workers 5 > out/sprint6/esB.out 2>&1
