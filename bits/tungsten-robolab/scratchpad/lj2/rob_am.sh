#!/bin/sh
cd /Users/erik/tungsten/bits/tungsten-robolab
export ROBOLAB_CALIB=v4 ROBOLAB_PROFILE=p95 ROBOLAB_PROFILE_PARTS=strength,speed,tendon,activation ROBOLAB_LJ_APPROACH=44
while [ ! -f out/long_jump_limits/rob_f3.done ]; do sleep 10; done
.venv/bin/python playground/long_jump_limits.py robust out/long_jump_limits/ik_am.txt --captures am_nom,am_s8003,am_s8006,am_s8007,am_s8008,am_s8009,am_s8010,am_s8011,am_s8013,am_s8014,am_s8015,am_s8016,am_s8017,am_s8018,am_s8019,am_s8021,am_s8022,am_s8023,am_s8025,am_s8028 --nk 19 --evals 300000 --workers 2 --sigma 0.04 --g0 0.3 --lmax=-1.5 --out out/long_jump_limits/rob_am.txt > out/long_jump_limits/rob_am.log 2>&1
echo done > out/long_jump_limits/rob_am.done
