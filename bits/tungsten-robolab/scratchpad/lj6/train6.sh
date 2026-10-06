#!/bin/sh
# L6: a risk-seeking robust stage via scratchpad/lj6/ljx_risk.py (LABELLED beyond-human body, unlimited run-up, check mark 151.025).
# usage: train6.sh <tag> <train-list-file> <evals> <init-program> [extra ljx_risk args]   (6 workers by default; WORKERS=5 leaves one for the monitor)
# program snapshots out/lj6/rk_<tag>.txt every 10 generations, log out/lj6/rk_<tag>.log, `touch out/lj6/rk_<tag>.txt.stop` stops it cleanly at the next snapshot
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
. scratchpad/lj6/env6.sh
export ROBOLAB_LJ_APPROACH=151.025 ROBOLAB_LJ_MARGIN=${MARGIN:-0.03}
tag=$1; list=$2; ev=$3; init=$4; shift 4
rm -f out/lj6/rk_${tag}.done out/lj6/rk_${tag}.txt.stop
nice -n 10 .venv/bin/python scratchpad/lj6/ljx_risk.py out/lj3/ik_bs45_b20.txt --captures "$(cat $list)" --nk 24 --evals $ev --init $init --kc --fmin 1.5 --floor 0 \
  --out out/lj6/rk_${tag}.txt --workers ${WORKERS:-6} --margin ${MARGIN:-0.03} --lmax -1.0 --lw 1.0 --pw 3.5 --grfcap 20 --grfw 0.3 --sigma ${SIGMA:-0.015} --pop ${POP:-100} "$@" > out/lj6/rk_${tag}.log 2>&1
echo done > out/lj6/rk_${tag}.done
