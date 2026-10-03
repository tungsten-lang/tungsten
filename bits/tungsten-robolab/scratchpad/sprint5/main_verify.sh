#!/bin/bash
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
echo "$(date '+%H:%M:%S') fresh check start" > out/sprint5/main_verify.log
nice -n 5 .venv/bin/python scratchpad/sprint5/fresh_check_main.py 2>&1 | grep -v -i "warn\|logger" >> out/sprint5/main_verify.log
echo "$(date '+%H:%M:%S') recheck start" >> out/sprint5/main_verify.log
nice -n 5 .venv/bin/python playground/arena.py recheck sprint_top_speed_v4_beyond_fresh128 sprint_top_speed_v4_beyond sprint_top_speed_v4_beyond_fresh128 2>&1 | grep -v -i "warn\|logger" >> out/sprint5/main_verify.log
echo "$(date '+%H:%M:%S') DONE" >> out/sprint5/main_verify.log
