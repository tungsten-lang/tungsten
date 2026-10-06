#!/bin/sh
# Q12b: after the running baseline CONFIRMATION evaluation: the remaining baseline CONFIRMATION run (if any) and K3 on 960 EXTRA fresh seeds 37001-37960 (never used by any pool, selection, confirmation or test: the pool zh2 covers 34601-35500 and zv 36001-36500, so 35001-35960 would have been contaminated).
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
while pgrep -f "scratchpad/lj6/ev6.sh" > /dev/null; do sleep 3; done
rm -f out/lj6/q12.done
T=long_jump_v4_beyond_robust96
[ -f out/lj6/ev_C7_32001-32480.json ] || scratchpad/lj6/ev6.sh C7 $T params/long_jump_beyond_rob2.txt bin/challengers/long_jump_run_y-l4b 32001-32480 6
[ -f out/lj6/ev_L3_32001-32480.json ] || scratchpad/lj6/ev6.sh L3 $T playground/arena/params/long_jump_v4_beyond_robust96-20260930-190409.txt bin/champions/long_jump_v4_beyond_robust96-20260930-190409 32001-32480 6
scratchpad/lj6/ev6.sh K3 $T scratchpad/lj6/params/long_jump_beyond_bo6a.txt bin/challengers/long_jump_run_y-l6a 37001-37960 6
echo done > out/lj6/q12.done
