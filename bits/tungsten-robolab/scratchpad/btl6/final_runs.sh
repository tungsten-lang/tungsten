#!/bin/bash
# final_runs.sh CAND_CTL CAND_PARAMS TAG : TEST G (82001-82064), TEST H (82065-82128), EXTRA (83001-83256), 15 s, 6 workers: the baseline G (btl5-a + final_g.txt) ONCE
# and the candidate ONCE each; logs and streak files out/btl6/final_<name>.{log,streaks}; run from bits/tungsten-robolab in the background
cd /Users/erik/tungsten/bits/tungsten-robolab
CTL=$1; PAR=$2; TAG=$3
: > out/btl6/final_$TAG.progress
for S in "TG 82001 82065" "TH 82065 82129" "X 83001 83257"; do
  set -- $S
  scratchpad/btl6/run_set.sh final_${TAG}_cand_$1 $CTL $PAR $2 $3 15 "" 6
  echo "done cand $1 $(date +%H:%M:%S)" >> out/btl6/final_$TAG.progress
  if [ ! -f out/btl6/final_base_$1.streaks ]; then
    scratchpad/btl6/run_set.sh final_base_$1 bin/challengers/btl5-a scratchpad/btl5/params/final_g.txt $2 $3 15 "" 6
    echo "done base $1 $(date +%H:%M:%S)" >> out/btl6/final_$TAG.progress
  fi
done
echo ALL >> out/btl6/final_$TAG.progress
