#!/bin/sh
# L6: assemble a candidate (H011 runner + take-off program + landing table + joint board shift) and run it on seed sets. LABELLED beyond-human body, unlimited run-up.
# usage: cand6.sh <tag> <program.txt> <landing.txt> <shift> <seeds> [<seeds> ...]    -> out/lj6/par_<tag>.txt, out/lj6/ev_<tag>_<seeds>.json
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
tag=$1; prog=$2; land=$3; sh=$4; shift 4
g0=$(grep -E "^ik_gap0 " $prog | tail -1 | awk '{print $2}')
g=$(python3 -c "print(repr($g0 - $sh))")
.venv/bin/python scratchpad/lj2/assemble.py out/lj6/par_$tag.txt out/lj6/A2h_011.txt $prog $land j_board_shift=$sh ik_gap0=$g > /dev/null
for s in "$@"; do
  scratchpad/lj6/ev6.sh $tag long_jump_v4_beyond_robust96 out/lj6/par_$tag.txt bin/challengers/long_jump_run_y-l4b $s 6
done
