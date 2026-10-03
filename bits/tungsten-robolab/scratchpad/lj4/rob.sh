#!/bin/sh
# robust stage via scratchpad/lj4/ljx_robust.py (LABELLED BEYOND-HUMAN BODY, UNLIMITED RUN-UP, check mark 151.025): rob.sh <tag> <train-list-file> <evals> <ik-base-file> [extra ljx_robust args]  (6 workers). L4
# (a copy of scratchpad/lj3/rob.sh with L4's paths; logs / programs in out/lj4/rob_<tag>.*, pid file out/lj4/rob_<tag>.pid written by the caller)
cd /Users/erik/tungsten/bits/tungsten-robolab
. scratchpad/lj4/env.sh
export ROBOLAB_LJ_APPROACH=151.025 ROBOLAB_LJ_MARGIN=${MARGIN:-0.03}
tag=$1; list=$2; ev=$3; base=$4; shift 4
rm -f out/lj4/rob_${tag}.done
nice -n 10 .venv/bin/python scratchpad/lj4/ljx_robust.py $base --captures "$(cat $list)" --nk 24 --evals $ev --out out/lj4/rob_${tag}.txt --workers ${WORKERS:-6} --margin ${MARGIN:-0.03} "$@" > out/lj4/rob_${tag}.log 2>&1
echo done > out/lj4/rob_${tag}.done
