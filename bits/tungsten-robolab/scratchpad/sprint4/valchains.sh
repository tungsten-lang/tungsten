#!/bin/sh
# valchains.sh SEEDS SECS WORKERS OUT chainfile... -- standing-start validation of chain files (30 s runs) on the beyond body; one summary block per chain appended to OUT
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
S=$1; T=$2; W=$3; O=$4; shift 4
for C in "$@"; do
  echo "== $C" >> $O
  scratchpad/sprint4/rep.sh $C bin/challengers/run_gearx-s4a $S $T $W 2>&1 | grep -E "FELL|falls|survivors" | cut -c1-110 >> $O
done
echo DONE >> $O
