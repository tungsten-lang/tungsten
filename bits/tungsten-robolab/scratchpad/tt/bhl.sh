#!/bin/sh
# Contact-timed backhand swing (bh_lead, round 5) re-tested on run 21's backhand: 200 independent pool serves. 3 workers, sequential; waits for tsl.sh.
cd /Users/erik/tungsten/bits/tungsten-robolab
while pgrep -f "[t]sl.sh" > /dev/null; do sleep 10; done
O=bin/challengers/myo_tt_r10-o; C2=params/myo_tt_p2_r10_c2.txt
for l in 0.42 0.47 0.52; do
  scratchpad/tt/ev1.sh val_bh_bhl$l $C2 $O scratchpad/tt/bh_val200.txt "bh_lead=$l" 3
done
