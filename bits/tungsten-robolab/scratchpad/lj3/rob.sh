#!/bin/sh
# robust stage via ljx_robust.py: rob.sh <tag> <train-list-file> <evals> <ik-base-or-init...> [extra args]  (6 workers). L3
cd /Users/erik/tungsten/bits/tungsten-robolab
. scratchpad/lj3/env.sh
export ROBOLAB_LJ_APPROACH=151.025 ROBOLAB_LJ_MARGIN=0.03
tag=$1; list=$2; ev=$3; base=$4; shift 4
rm -f out/lj3/rob_${tag}.done
nice -n 10 .venv/bin/python scratchpad/lj3/ljx_robust.py $base --captures "$(cat $list)" --nk 24 --evals $ev --out out/lj3/rob_${tag}.txt --workers 6 "$@" > out/lj3/rob_${tag}.log 2>&1
echo done > out/lj3/rob_${tag}.done
