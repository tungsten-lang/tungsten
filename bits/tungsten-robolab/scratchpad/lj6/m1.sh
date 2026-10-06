#!/bin/sh
# M1: the two baselines on the SELECTION set 31001-31480 (LABELLED beyond-human body, unlimited run-up)
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
rm -f out/lj6/m1.done
scratchpad/lj6/ev6.sh C7 long_jump_v4_beyond_robust96 params/long_jump_beyond_rob2.txt bin/challengers/long_jump_run_y-l4b 31001-31480 6
scratchpad/lj6/ev6.sh L3 long_jump_v4_beyond_robust96 playground/arena/params/long_jump_v4_beyond_robust96-20260930-190409.txt bin/champions/long_jump_v4_beyond_robust96-20260930-190409 31001-31480 6
echo done > out/lj6/m1.done
