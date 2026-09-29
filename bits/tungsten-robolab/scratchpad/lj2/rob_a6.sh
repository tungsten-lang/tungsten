#!/bin/sh
# robust take-off program for the one-step-longer steering horizon (A6 = A4c + j_st_n 6): warm start from rob_a4_final, 32 gap-stratified a6 states of both plant sides
# (scratchpad/lj2/select_train.py a6), 4 workers, 200k sims. usage: rob_a6.sh [evals] [workers]
cd /Users/erik/tungsten/bits/tungsten-robolab
export ROBOLAB_CALIB=v4 ROBOLAB_PROFILE=p95 ROBOLAB_PROFILE_PARTS=strength,speed,tendon,activation ROBOLAB_LJ_APPROACH=44
TR=$(cat scratchpad/lj2/a6_train.txt | tr -d '\n')
.venv/bin/python playground/long_jump_limits.py robust out/long_jump_limits/rob_a4_final.txt --init out/long_jump_limits/rob_a4_final.txt --captures $TR --nk 19 --evals ${1:-200000} --workers ${2:-4} --sigma 0.03 --g0 0.3 --lmax=-1.5 --risk 0.3 --out out/long_jump_limits/rob_a6.txt > out/long_jump_limits/rob_a6.log 2>&1
echo done > out/long_jump_limits/rob_a6.done
