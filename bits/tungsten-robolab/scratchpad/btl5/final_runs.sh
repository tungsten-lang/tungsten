#!/bin/bash
# final_runs.sh CAND_CTL CAND_PARAMS TAG : TEST E (22001-22064), TEST F (22065-22128), EXTRA (23001-23256), 15 s, 6 workers:
# the baseline (btl4-final + final_f.txt) ONCE and the candidate ONCE; logs and streak files in out/btl5/final_<TAG>_*; run from bits/tungsten-robolab in the background
CTL=$1; PAR=$2; TAG=$3
run() { # name ctl params s0 s1
  scratchpad/btl5/py scratchpad/btl2/chain.py $2 $3 $4 $5 15 "" 6 > out/btl5/final_$1.log 2>&1
  grep -E "^[0-9]+ streak" out/btl5/final_$1.log | awk '{print $1, $3}' > out/btl5/final_$1.streaks
  echo "done $1 $(date +%H:%M:%S)" >> out/btl5/final_$TAG.progress
}
: > out/btl5/final_$TAG.progress
for S in "E 22001 22065" "F 22065 22129" "X 23001 23257"; do
  set -- $S
  run ${TAG}_cand_$1 $CTL $PAR $2 $3
  if [ ! -f out/btl5/final_base_$1.streaks ]; then
    run base_$1 bin/challengers/btl4-final scratchpad/btl4/params/final_f.txt $2 $3
  fi
done
echo ALL DONE >> out/btl5/final_$TAG.progress
