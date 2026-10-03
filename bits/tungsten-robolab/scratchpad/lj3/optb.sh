#!/bin/sh
# board-mode ideal search via ljx.py: optb.sh <capture> <tag> <boardx> <evals> <sigma> <pop> <init.json> [extra ljx args...]  (6 workers). L3
cd /Users/erik/tungsten/bits/tungsten-robolab
. scratchpad/lj3/env.sh
export ROBOLAB_LJ_APPROACH=$3
cap=$1; tag=$2; ev=$4; sig=$5; pop=$6; init=$7; shift 7
rm -f out/lj3/ljx_${cap}_${tag}.done
nice -n 10 .venv/bin/python scratchpad/lj3/ljx.py opt $cap --tag $tag --evals $ev --sigma $sig --pop $pop --init $init --workers 6 --board --margin 0.03 "$@" > out/lj3/ljx_${cap}_${tag}.log 2>&1
echo done > out/lj3/ljx_${cap}_${tag}.done
