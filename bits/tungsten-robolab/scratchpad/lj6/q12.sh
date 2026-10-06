#!/bin/sh
# Q12 (after the TEST runs): the baselines on CONFIRMATION 32001-32480 (paired tables) and K3 on 960 EXTRA fresh seeds 35001-35960 (declared: not a choice set, a tighter estimate of the final candidate's rate).
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
while [ ! -f out/lj6/final_K3.done ]; do sleep 5; done
rm -f out/lj6/q12.done
T=long_jump_v4_beyond_robust96
scratchpad/lj6/ev6.sh C7 $T params/long_jump_beyond_rob2.txt bin/challengers/long_jump_run_y-l4b 32001-32480 6
scratchpad/lj6/ev6.sh L3 $T playground/arena/params/long_jump_v4_beyond_robust96-20260930-190409.txt bin/champions/long_jump_v4_beyond_robust96-20260930-190409 32001-32480 6
scratchpad/lj6/ev6.sh K3 $T scratchpad/lj6/params/long_jump_beyond_bo6a.txt bin/challengers/long_jump_run_y-l6a 35001-35960 6
echo done > out/lj6/q12.done
