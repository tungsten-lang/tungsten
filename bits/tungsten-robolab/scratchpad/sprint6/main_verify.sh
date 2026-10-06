#!/bin/bash
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
mkdir -p out/sprint6
echo "$(date '+%H:%M:%S') fresh check start" > out/sprint6/main_verify.log
nice -n 5 .venv/bin/python scratchpad/sprint6/fresh_check_main.py bin/challengers/run_gearz-s6-final params/run_gearz_v4_beyond_s6a.txt 50001 50512 2>&1 | grep -v -i "warn\|logger" >> out/sprint6/main_verify.log
echo "$(date '+%H:%M:%S') DONE" >> out/sprint6/main_verify.log
