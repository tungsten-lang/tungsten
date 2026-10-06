#!/bin/sh
# L6: lists of a captured pool (gap-ordered, every 2nd state held out) and the calibrated surrogate of a take-off program on all of its states.
# usage: poolcmp.sh <prefix> <first_seed> <last_seed> <program.txt> [shift ...]
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
. scratchpad/lj6/env6.sh
export ROBOLAB_LJ_APPROACH=151.025 ROBOLAB_LJ_MARGIN=0.03
pre=$1; a=$2; b=$3; prog=$4; shift 4
[ -f out/lj6/${pre}_all.txt ] || .venv/bin/python scratchpad/lj4/mklist.py $pre $a $b out/lj6/$pre 2 1
n=$(tr ',' '\n' < out/lj6/${pre}_all.txt | wc -l)
echo "pool $pre: $n captured of $((b - a + 1)) seeds = $(python3 -c "print(round(100*$n/($b-$a+1),1))") %"
for sh in "$@"; do
  echo "-- $prog on pool $pre (all $n states), shift $sh"
  nice -n 10 .venv/bin/python scratchpad/lj6/ljx_risk.py --eval $prog --captures "$(cat out/lj6/${pre}_all.txt)" --fmin 1.5 --workers 3 --lmax -1.0 --lw 1.0 --pw 3.5 --quiet --shift $sh 2>&1 | grep -E "SUMMARY|^TAIL|vz"
done
