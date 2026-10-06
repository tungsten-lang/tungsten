#!/bin/sh
# Q2: calibration of the harness against the official rollouts: C7 (params/long_jump_beyond_rob2.txt, l4b) on the 711 held-out pool seeds (8001-9100 subset; NOT selection seeds).
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
while [ ! -f out/lj6/q1b.done ]; do sleep 5; done
rm -f out/lj6/q2.done
scratchpad/lj6/ev6l.sh calC7 long_jump_v4_beyond_robust96 params/long_jump_beyond_rob2.txt bin/challengers/long_jump_run_y-l4b out/lj6/held711_seeds.txt 6
echo done > out/lj6/q2.done
