#!/bin/sh
cd /Users/erik/tungsten/bits/tungsten-robolab
export ROBOLAB_CALIB=v4 ROBOLAB_PROFILE=p95 ROBOLAB_PROFILE_PARTS=strength,speed,tendon,activation ROBOLAB_LJ_APPROACH=44
.venv/bin/python playground/long_jump_limits.py robust out/long_jump_limits/rob_am_g340.txt --init out/long_jump_limits/rob_am_g340.txt --captures a4_s8124,a4_s8090,a4_s8028,a4_s8062,a4_s8084,a4_s8123,a4_s8042,a4_s8017,a4_s8019,a4_s8051,a4_s8061,a4_s8107,a4_s8065,a4_s8027,a4_s8110,a4_s8036,a4_s8114,a4_s8077,a4_s8095,a4_s8106,a4_s8023,a4_s8044,a4_s8125,a4_s8089,a4_s8039,a4_s8086,a4_s8033,a4_s8096,a4_s8072,a4_s8127,a4_s8094,a4_s8085 --nk 19 --evals 400000 --workers 2 --sigma 0.03 --g0 0.3 --lmax=-1.5 --risk 0.3 --out out/long_jump_limits/rob_a4.txt > out/long_jump_limits/rob_a4.log 2>&1
echo done > out/long_jump_limits/rob_a4.done
