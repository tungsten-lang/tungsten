#!/bin/sh
# Backhand stage-4 candidates (rsm_bh6: dynamics around c3) on the 200 independent pool serves bh[100:300]; c3's backhand scored 79/200 there (val_bh_s3_step05). r10-o, 3 workers.
cd /Users/erik/tungsten/bits/tungsten-robolab
O=bin/challengers/myo_tt_r10-o
for c in step1 step05 run7 run18; do
  scratchpad/tt/ev1.sh val_bh_s4_$c params/myo_tt_p2_r10_bh6_$c.txt $O scratchpad/tt/bh_val200.txt "" 3
done
