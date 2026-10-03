#!/bin/sh
# tails experiment on L3's r3 (harness only): per-regime post-touchdown offsets trained on the T pool (seeds 8001-8700), evaluated on the H pool (8701-9100). L4
cd /Users/erik/tungsten/bits/tungsten-robolab
. scratchpad/lj4/env.sh
export ROBOLAB_LJ_APPROACH=151.025 ROBOLAB_LJ_MARGIN=0.03
rm -f out/lj4/tail1.done
for reg in 2 1; do
  nice -n 10 .venv/bin/python scratchpad/lj4/ljx_tail.py train out/lj3/rob_r3_snap.txt --captures "$(cat out/lj4/y2T.txt)" --fmin 1.5 --regime $reg --t1 0.20 --t2 0.26 --evals ${EV:-400000} --sigma 0.05 --workers 6 --out out/lj4/tail1_r$reg.npz > out/lj4/tail1_r$reg.log 2>&1
done
nice -n 10 .venv/bin/python scratchpad/lj4/ljx_tail.py eval out/lj3/rob_r3_snap.txt --captures "$(cat out/lj4/y2H.txt)" --fmin 1.5 --t1 0.20 --t2 0.26 --tails out/lj4/tail1_r2.npz,out/lj4/tail1_r1.npz > out/lj4/tail1_eval_H.txt 2>&1
nice -n 10 .venv/bin/python scratchpad/lj4/ljx_tail.py eval out/lj3/rob_r3_snap.txt --captures "$(cat out/lj4/y2T.txt)" --fmin 1.5 --t1 0.20 --t2 0.26 --tails out/lj4/tail1_r2.npz,out/lj4/tail1_r1.npz > out/lj4/tail1_eval_T.txt 2>&1
echo done > out/lj4/tail1.done
