#!/bin/sh
# like ev6.sh for a LONG seed list in a file: ev6l.sh <tag> <trial> <params> <controller> <seeds-file> <workers> [extra args] -> out/lj6/ev_<tag>.json/.txt
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
. scratchpad/lj6/env6.sh
tag=$1; trial=$2; params=$3; ctl=$4; sf=$5; workers=$6
shift 6
nice -n 10 .venv/bin/python playground/long_jump_eval.py "$trial" --params "$params" --controller "$ctl" --task long_jump_v4_beyond_a \
  --seeds "$(cat $sf)" --workers "$workers" --out "out/lj6/ev_${tag}.json" "$@" > "out/lj6/ev_${tag}.txt" 2>&1
