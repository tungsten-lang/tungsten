#!/bin/sh
# phase 2a: freeze the take-off program R1 (the Rb1 snapshot at the time of the call), then train the regime tails on it (union pool T + H, 1041 states). L4
cd /Users/erik/tungsten/bits/tungsten-robolab
. scratchpad/lj4/env.sh
export ROBOLAB_LJ_APPROACH=151.025 ROBOLAB_LJ_MARGIN=0.03
rm -f out/lj4/phase2a.done
for reg in 2 1; do
  nice -n 10 .venv/bin/python scratchpad/lj4/ljx_tail.py train out/lj4/R1.txt --captures "$(cat out/lj4/y2TH.txt)" --fmin 1.5 --regime $reg --t1 0.20 --t2 0.26 --evals ${EV:-300000} --sigma 0.05 --workers 6 --out out/lj4/tail2_r$reg.npz > out/lj4/tail2_r$reg.log 2>&1
done
.venv/bin/python scratchpad/lj4/mktails.py out/lj4/tails2.txt out/lj4/tail2_r1.npz out/lj4/tail2_r2.npz > out/lj4/mktails2.log 2>&1
echo done > out/lj4/phase2a.done
