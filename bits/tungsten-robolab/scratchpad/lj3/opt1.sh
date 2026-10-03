#!/bin/sh
# ideal-control search on capture $1 (tag $2, evals $3, workers $4, optional init json $5); foot-mode D, lmax -1.5. L3.
cd /Users/erik/tungsten/bits/tungsten-robolab
. scratchpad/lj3/env.sh
export ROBOLAB_LJ_APPROACH=${BOARDX:-150.35}
INIT=""
[ -n "$5" ] && INIT="--init $5"
nice -n 10 .venv/bin/python playground/long_jump_limits.py optimise $1 --evals $3 --workers ${4:-6} --lmax=${LMAX:--1.5} --tag $2 $INIT > out/lj3/opt_$1_$2.log 2>&1
echo done > out/lj3/opt_$1_$2.done
