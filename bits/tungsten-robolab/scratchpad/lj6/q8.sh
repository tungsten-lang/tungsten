#!/bin/sh
# Q8: (1) rollouts of the Rk1 generation-10 snapshot (K2 = H011 runner + Rk1 gen-10 take-off + land_C2 + joint shift 0.10) on SELECTION; (2) the larger H pools: zh2 = seeds 34601-35500 (training), zv = seeds 36001-36500 (held-out).
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
rm -f out/lj6/q8.done
scratchpad/lj6/ev6.sh K2 long_jump_v4_beyond_robust96 out/lj6/par_K2.txt bin/challengers/long_jump_run_y-l4b 31001-31480 6
scratchpad/lj6/capset6.sh out/lj6/A2h_011.txt zh2 bin/challengers/long_jump_run_y-l4b 34601-35500 6 2>/dev/null || scratchpad/lj6/capset6.sh out/lj6/A2h_011.txt zh2 bin/challengers/long_jump_run_y-l4b 34601 35500 6
scratchpad/lj6/capset6.sh out/lj6/A2h_011.txt zv bin/challengers/long_jump_run_y-l4b 36001 36500 6
echo done > out/lj6/q8.done
