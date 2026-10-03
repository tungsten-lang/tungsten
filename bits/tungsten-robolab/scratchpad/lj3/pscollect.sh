#!/bin/sh
# per-state programs (latched, robust format) for the regression experiment: ljx_robust.py on ONE capture at a time, only the excitation knots free, from the
# one-start program, board mode, cap 20 BW, sigma 0.02, 60k candidates, 6 workers. L3
# usage: pscollect.sh <list-file> <tag> [init-program]      (waits for the flag file out/lj3/ps_go)
cd /Users/erik/tungsten/bits/tungsten-robolab
. scratchpad/lj3/env.sh
export ROBOLAB_LJ_APPROACH=151.025 ROBOLAB_LJ_MARGIN=0.03
list=$1; tag=$2; init=${3:-params/long_jump_beyond_nom1.txt}
while [ ! -f out/lj3/ps_go ]; do sleep 5; done
for st in $(cat $list | tr ',' ' '); do
  echo "run $st" >> out/lj3/pscollect_$tag.index
  nice -n 10 .venv/bin/python scratchpad/lj3/ljx_robust.py out/lj3/ik_bs45_b20.txt --captures $st --nk 24 --evals 60000 --workers 6 --sigma 0.02 --pop 200 --risk 0 \
     --floor -1 --grfcap 20 --grfw 0.3 --lmin -15 --only-e --init $init --out out/lj3/ps_${st}_$tag.txt > out/lj3/ps_${st}_$tag.log 2>&1
done
echo done > out/lj3/pscollect_$tag.done
