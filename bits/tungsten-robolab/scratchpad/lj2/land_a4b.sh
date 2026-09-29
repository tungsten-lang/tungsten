#!/bin/sh
# landing program, second stage (L2): all 117 valid hand-overs of the 125 a4 captures (both plant sides; the current take-off program a4_l60, no variants), t_left 2 s,
# warm start = the generation-60 snapshot of land_a4, sigma 0.03, tail 10 %, jitter. usage: land_a4b.sh <workers>
cd /Users/erik/tungsten/bits/tungsten-robolab
export ROBOLAB_CALIB=v4 ROBOLAB_PROFILE=p95 ROBOLAB_PROFILE_PARTS=strength,speed,tendon,activation ROBOLAB_LJ_APPROACH=44
.venv/bin/python playground/long_jump_limits.py landing --handover hoa4alls --capture a4_s8039 --rec reca4 --tg 0.60 --h 0.08 --nk 34 --lz 0.8 --evals 200000 --workers ${1:-2} --sigma 0.03 --risk 0.5 --g0 0.3 --ignore-foul --tail-q 0.1 --jitter --init scratchpad/lj2/land_a4_g60.txt --out out/long_jump_limits/land_a4b.txt > out/long_jump_limits/land_a4b.log 2>&1
echo done > out/long_jump_limits/land_a4b.done
