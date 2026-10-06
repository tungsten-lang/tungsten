#!/bin/sh
# L6: full rollouts of a candidate on a seed set (LABELLED beyond-human body, unlimited run-up; task long_jump_v4_beyond_a, check mark 151.025 m).
# usage: ev6.sh <tag> <trial> <params> <controller> <seeds> <workers> [extra long_jump_eval.py args]
# writes out/lj6/ev_<tag>_<seeds>.json and .txt ; thread caps + nice per the coordinator.
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
. scratchpad/lj6/env6.sh
tag=$1; trial=$2; params=$3; ctl=$4; seeds=$5; workers=$6
shift 6
nice -n 10 .venv/bin/python playground/long_jump_eval.py "$trial" --params "$params" --controller "$ctl" --task long_jump_v4_beyond_a \
  --seeds "$seeds" --workers "$workers" --out "out/lj6/ev_${tag}_${seeds}.json" "$@" > "out/lj6/ev_${tag}_${seeds}.txt" 2>&1
