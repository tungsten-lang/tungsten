#!/bin/sh
# Q7: paired training pools (seeds 34001-34600; training seeds, new captures from 34001 on): H = chain H011 (F1 start + chain D gears 2+3, SB2) and D = chain D (SB2), controller l4b.
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
rm -f out/lj6/q7.done
scratchpad/lj6/capset6.sh out/lj6/A2h_011.txt zh bin/challengers/long_jump_run_y-l4b 34001 34600 6
scratchpad/lj6/capset6.sh out/lj6/A2i_1.txt zd bin/challengers/long_jump_run_y-l4b 34001 34600 6
echo done > out/lj6/q7.done
