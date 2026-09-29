#!/bin/sh
# Side boundary with c2's better backhand: y_switch 0.25 and 0.4 on the 600 fresh serves of block 1 (paired against mix_c2). 3 workers, sequential.
cd /Users/erik/tungsten/bits/tungsten-robolab
for y in 0.25 0.4; do
  TT_ENV=P2 .venv-myo/bin/python playground/tt_eval.py --params params/myo_tt_p2_r10_c2.txt --controller bin/challengers/myo_tt_r10-o --seeds 710000:710600 --out out/tt_r10/mix_c2_ysw$y.jsonl --workers 3 --set "y_switch=$y" > out/tt_r10/mix_c2_ysw$y.log 2>&1
done
