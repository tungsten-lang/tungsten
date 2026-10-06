#!/bin/sh
# L7: lists of a captured pool (gap-ordered, every k-th state held out) and the calibrated surrogate of a take-off program on all of its states at several joint shifts.
# usage: poolcmp7.sh <prefix> <first_seed> <last_seed> <program.txt> <workers> [shift ...]      (per-start rows: out/lj7/rows_<prefix>_<progtag>_<shift>.json)
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
. scratchpad/lj7/env7.sh
export ROBOLAB_LJ_APPROACH=151.025 ROBOLAB_LJ_MARGIN=0.03
pre=$1; a=$2; b=$3; prog=$4; w=$5; shift 5
[ -f out/lj7/${pre}_all.txt ] || .venv/bin/python scratchpad/lj4/mklist.py $pre $a $b out/lj7/$pre 2 1
n=$(tr ',' '\n' < out/lj7/${pre}_all.txt | wc -l)
tag=$(basename $prog .txt)
echo "pool $pre: $n captured of $((b - a + 1)) seeds = $(python3 -c "print(round(100*$n/($b-$a+1),1))") %"
for sh in "$@"; do
  echo "-- $tag on pool $pre (all $n states), shift $sh"
  nice -n 10 .venv/bin/python scratchpad/lj6/ljx_risk.py --eval $prog --captures "$(cat out/lj7/${pre}_all.txt)" --fmin 1.5 --workers $w --lmax -1.0 --lw 1.0 --pw 3.5 --quiet --shift $sh --json out/lj7/rows_${pre}_${tag}_${sh}.json 2>&1 | grep -E "SUMMARY|^TAIL|vz"
done
