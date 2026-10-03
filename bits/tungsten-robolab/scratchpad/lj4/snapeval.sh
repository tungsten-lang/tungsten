#!/bin/sh
# harness evaluation of a robust program snapshot on a list of captured states (the LABELLED BEYOND-HUMAN body states): snapeval.sh <prog.txt> <list-file> [fmin]
cd /Users/erik/tungsten/bits/tungsten-robolab
. scratchpad/lj4/env.sh
export ROBOLAB_LJ_APPROACH=151.025 ROBOLAB_LJ_MARGIN=0.03
nice -n 10 .venv/bin/python scratchpad/lj4/ljx_robust.py --eval $1 --captures "$(cat $2)" --fmin ${3:-1.5} 2>&1 | tail -1
