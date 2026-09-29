#!/bin/sh
cd /Users/erik/tungsten/bits/tungsten-robolab
export ROBOLAB_CALIB=v4 ROBOLAB_PROFILE=p95 ROBOLAB_PROFILE_PARTS=strength,speed,tendon,activation ROBOLAB_LJ_APPROACH=44
.venv/bin/python playground/long_jump_limits.py robust out/long_jump_limits/ik_f3.txt --captures f3_nom,f3_s8003,f3_s8006,f3_s8007,f3_s8008,f3_s8009,f3_s8010,f3_s8011,f3_s8013,f3_s8014,f3_s8015,f3_s8016,f3_s8017,f3_s8018,f3_s8019,f3_s8021,f3_s8022,f3_s8023,f3_s8025,f3_s8028 --nk 19 --evals 300000 --workers 2 --sigma 0.04 --g0 0.3 --lmax=-1.5 --out out/long_jump_limits/rob_f3.txt > out/long_jump_limits/rob_f3.log 2>&1
echo done > out/long_jump_limits/rob_f3.done
