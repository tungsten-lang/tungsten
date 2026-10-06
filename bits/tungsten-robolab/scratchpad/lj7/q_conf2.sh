#!/bin/sh
# L7: CONFIRMATION (62001-62480) of the final candidate l7a (params scratchpad/lj7/params/long_jump_beyond_l7a.txt, controller l7a)
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
while [ ! -f out/lj7/q_sel2.done ]; do sleep 3; done
rm -f out/lj7/q_conf2.done
scratchpad/lj7/ev7.sh l7a long_jump_v4_beyond_robust96 scratchpad/lj7/params/long_jump_beyond_l7a.txt bin/challengers/long_jump_run_y-l7a 62001-62480 6
echo done > out/lj7/q_conf2.done
