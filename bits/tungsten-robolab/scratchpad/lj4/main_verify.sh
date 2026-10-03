#!/bin/bash
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
mkdir -p out/lj4
echo "$(date '+%H:%M:%S') fresh check start" > out/lj4/main_verify.log
nice -n 5 .venv/bin/python scratchpad/lj4/fresh_check_main.py 2>&1 | grep -v -i "warn\|logger" >> out/lj4/main_verify.log
echo "$(date '+%H:%M:%S') recheck start" >> out/lj4/main_verify.log
nice -n 5 .venv/bin/python playground/arena.py recheck long_jump_v4_beyond long_jump_v4_beyond_robust long_jump_v4_beyond_robust96 2>&1 | grep -v -i "warn\|logger" >> out/lj4/main_verify.log
echo "$(date '+%H:%M:%S') DONE" >> out/lj4/main_verify.log
