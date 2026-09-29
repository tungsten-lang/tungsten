#!/bin/sh
# Contact-timed servo start (r10-o): forehand ts_lead and backhand bh_ts_lead scans on the 200 independent pool serves of each side. 3 workers, sequential.
cd /Users/erik/tungsten/bits/tungsten-robolab
O=bin/challengers/myo_tt_r10-o; C2=params/myo_tt_p2_r10_c2.txt
for l in 0.20 0.235 0.27; do
  scratchpad/tt/ev1.sh val_fh_tsl$l $C2 $O scratchpad/tt/fh_val200.txt "ts_lead=$l" 3
done
for l in 0.20 0.23 0.26; do
  scratchpad/tt/ev1.sh val_bh_tsl$l $C2 $O scratchpad/tt/bh_val200.txt "bh_ts_lead=$l" 3
done
