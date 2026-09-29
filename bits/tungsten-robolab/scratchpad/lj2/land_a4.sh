#!/bin/sh
# landing program for the A4 take-off (L2): 62 hand-overs (32 gap-stratified starts + 1 execution-noise variant each, both plant sides), the recorded chunk landing of seed 8039 as the base,
# ballistic-time clock tg 0.60, sand latch below 0.8 m, tail-weighted (worst 10 %), timing jitter
cd /Users/erik/tungsten/bits/tungsten-robolab
export ROBOLAB_CALIB=v4 ROBOLAB_PROFILE=p95 ROBOLAB_PROFILE_PARTS=strength,speed,tendon,activation ROBOLAB_LJ_APPROACH=44
.venv/bin/python playground/long_jump_limits.py landing --handover hoa4s --capture a4_s8039 --rec reca4 --tg 0.60 --h 0.08 --nk 34 --lz 0.8 --evals 300000 --workers 2 --sigma 0.06 --risk 0.5 --g0 0.3 --ignore-foul --tail-q 0.1 --jitter --out out/long_jump_limits/land_a4.txt > out/long_jump_limits/land_a4.log 2>&1
echo done > out/long_jump_limits/land_a4.done
