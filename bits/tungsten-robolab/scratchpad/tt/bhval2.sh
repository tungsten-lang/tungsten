#!/bin/sh
# Backhand validation, second batch on the same 200 independent pool serves: other RSM runs and a bh_gain scan around run 21. 3 workers, sequential.
cd /Users/erik/tungsten/bits/tungsten-robolab
K=bin/challengers/myo_tt_r10-k
for r in 27 11 5; do
  .venv-myo/bin/python playground/tt_rsm_run_params.py --out out/tt_r10/rsm_bh3 --run $r --write params/myo_tt_p2_r10_bh_run$r.txt
  scratchpad/tt/ev1.sh val_bh_run$r params/myo_tt_p2_r10_bh_run$r.txt $K scratchpad/tt/bh_val200.txt "" 3
done
for g in 0.90 0.94 0.96; do
  scratchpad/tt/ev1.sh val_bh_run21_g$g params/myo_tt_p2_r10_bh_run21.txt $K scratchpad/tt/bh_val200.txt "bh_gain=$g" 3
done
