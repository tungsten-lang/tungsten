#!/bin/sh
# Q11 (LABELLED beyond-human body, unlimited run-up): K4 = H011 + TO1 + landing L1 (20 generations on strong hand-overs) + shift 0.10 on SELECTION; K3 on CONFIRMATION 32001-32480.
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
rm -f out/lj6/q11.done
scratchpad/lj6/cand6.sh K4 out/lj6/TO1.txt out/lj6/land_L1.txt 0.10 31001-31480
scratchpad/lj6/ev6.sh K3 long_jump_v4_beyond_robust96 out/lj6/par_K3.txt bin/challengers/long_jump_run_y-l4b 32001-32480 6
echo done > out/lj6/q11.done
