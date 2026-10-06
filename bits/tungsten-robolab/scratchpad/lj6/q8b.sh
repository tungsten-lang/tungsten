#!/bin/sh
# Q8b: after the running K2 evaluation: the larger H pools: zh2 = seeds 34601-35500 (training), zv = seeds 36001-36500 (held-out), runner H011 (A2h_011), controller l4b.
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
while pgrep -f "scratchpad/lj6/ev6.sh K2" > /dev/null; do sleep 3; done
rm -f out/lj6/q8.done
scratchpad/lj6/capset6.sh out/lj6/A2h_011.txt zh2 bin/challengers/long_jump_run_y-l4b 34601 35500 6
scratchpad/lj6/capset6.sh out/lj6/A2h_011.txt zv bin/challengers/long_jump_run_y-l4b 36001 36500 6
echo done > out/lj6/q8.done
