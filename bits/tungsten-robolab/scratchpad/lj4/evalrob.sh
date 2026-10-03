#!/bin/sh
# assemble approach + take-off program (+ landing table) into out/lj4/par_<tag>.txt and run full rollouts on <seeds> of trial long_jump_v4_beyond (task long_jump_v4_beyond_a, board 151.025;
# controller long_jump_run_y-l4a by default; LABELLED BEYOND-HUMAN BODY, UNLIMITED RUN-UP). L4 (adapted from scratchpad/lj3/evalrob.sh)
# usage: evalrob.sh <tag> <seeds> <workers> <approach.txt> <ik.txt> [il.txt] [k=v ...]
cd /Users/erik/tungsten/bits/tungsten-robolab
tag=$1; seeds=$2; workers=$3; app=$4; ik=$5; shift 5
files="$app $ik"
if [ $# -gt 0 ] && [ "${1%%=*}" = "$1" ]; then files="$files $1"; shift; fi
.venv/bin/python scratchpad/lj2/assemble.py out/lj4/par_$tag.txt $files "$@" > /dev/null
CTL=${CTL:-bin/challengers/long_jump_run_y-l4a}
nice -n 10 .venv/bin/python playground/long_jump_eval.py long_jump_v4_beyond --params out/lj4/par_$tag.txt --controller $CTL --task long_jump_v4_beyond_a --seeds $seeds --workers $workers --out out/lj4/ev_${tag}_$(echo $seeds | tr ',' '_').json
