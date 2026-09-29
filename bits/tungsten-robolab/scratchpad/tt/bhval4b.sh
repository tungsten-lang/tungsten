#!/bin/sh
cd /Users/erik/tungsten/bits/tungsten-robolab
while pgrep -f "[b]hval4.sh" > /dev/null; do sleep 10; done
scratchpad/tt/ev1.sh val_bh_s4_half params/myo_tt_p2_r10_bh6_half.txt bin/challengers/myo_tt_r10-o scratchpad/tt/bh_val200.txt "" 3
