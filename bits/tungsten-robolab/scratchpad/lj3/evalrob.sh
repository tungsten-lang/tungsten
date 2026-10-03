#!/bin/sh
# assemble approach + robust program (+ landing table) into out/lj3/par_<tag>.txt and run full rollouts on <seeds> of trial long_jump_v4_beyond (controller l3b by default).
# usage: evalrob.sh <tag> <seeds> <workers> <approach.txt> <ik.txt> [il.txt] [k=v ...]     (L3)
cd /Users/erik/tungsten/bits/tungsten-robolab
tag=$1; seeds=$2; workers=$3; app=$4; ik=$5; shift 5
files="$app $ik"
if [ $# -gt 0 ] && [ "${1%%=*}" = "$1" ]; then files="$files $1"; shift; fi
.venv/bin/python scratchpad/lj2/assemble.py out/lj3/par_$tag.txt $files "$@" > /dev/null
CTL=${CTL:-bin/challengers/long_jump_run_x-l3b}
nice -n 10 .venv/bin/python playground/long_jump_eval.py long_jump_v4_beyond --params out/lj3/par_$tag.txt --controller $CTL --task long_jump_v4_beyond_a --seeds $seeds --workers $workers --out out/lj3/ev_${tag}_$(echo $seeds | tr ',' '_').json
