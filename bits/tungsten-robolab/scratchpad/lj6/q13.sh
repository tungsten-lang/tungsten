#!/bin/sh
# Q13 (after q12b): K3 on L4's REFERENCE seeds 11001-11400 (comparable with the two stored 400-start files C7 / L3; a reference, never a choice), and K4 on CONFIRMATION (the variant's record).
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
while [ ! -f out/lj6/q12.done ]; do sleep 5; done
rm -f out/lj6/q13.done
T=long_jump_v4_beyond_robust96
scratchpad/lj6/ev6.sh K3 $T scratchpad/lj6/params/long_jump_beyond_bo6a.txt bin/challengers/long_jump_run_y-l6a 11001-11400 6
scratchpad/lj6/ev6.sh K4 $T out/lj6/par_K4.txt bin/challengers/long_jump_run_y-l4b 32001-32480 6
echo done > out/lj6/q13.done
