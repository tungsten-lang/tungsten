#!/bin/sh
cd /Users/erik/tungsten/bits/tungsten-robolab
export ROBOLAB_LJ_APPROACH=44
.venv/bin/python playground/long_jump_limits.py optimise v4p_s0 --evals 50000 --workers 3 --lmax inf --tag free --init out/long_jump_limits/v4p_s0_ideal.json > out/long_jump_limits/v4p_free.log 2>&1
.venv/bin/python playground/long_jump_limits.py optimise v4p_s0 --evals 50000 --workers 3 --lmax=-1.5 --tag back --init out/long_jump_limits/v4p_s0_ideal.json > out/long_jump_limits/v4p_back.log 2>&1
echo done > out/long_jump_limits/v4p_ideal.done
