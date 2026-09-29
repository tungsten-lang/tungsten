#!/bin/sh
# Backhand stage-3 candidates (posture, offsets: rsm_bh5) on the 200 independent pool serves bh[100:300]; run 21 (c2's backhand) scored 69/200 there. r10-n, 3 workers.
cd /Users/erik/tungsten/bits/tungsten-robolab
N=bin/challengers/myo_tt_r10-n
for c in step1 step05 run15 run9; do
  scratchpad/tt/ev1.sh val_bh_s3_$c params/myo_tt_p2_r10_bh5_$c.txt $N scratchpad/tt/bh_val200.txt "" 3
done
