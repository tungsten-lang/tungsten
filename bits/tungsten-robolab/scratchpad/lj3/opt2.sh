#!/bin/sh
# generic optimise launcher: opt2.sh <capture> <tag> <evals> <workers> <sigma> <pop> [init.json]   (env: BOARDX, LMAX, extra env passes through)
cd /Users/erik/tungsten/bits/tungsten-robolab
. scratchpad/lj3/env.sh
export ROBOLAB_LJ_APPROACH=${BOARDX:-150.35}
INIT=""
[ -n "$7" ] && INIT="--init $7"
nice -n 10 .venv/bin/python playground/long_jump_limits.py optimise $1 --evals $3 --workers ${4:-6} --sigma $5 --pop $6 --lmax=${LMAX:--1.5} --seed ${SEED:-1} --tag $2 $INIT > out/lj3/opt_$1_$2.log 2>&1
echo done > out/lj3/opt_$1_$2.done
