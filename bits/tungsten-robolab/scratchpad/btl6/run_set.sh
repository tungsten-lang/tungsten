#!/bin/bash
# run_set.sh TAG CTL PARAMS S0 S1 SECS [OVERRIDES] [WORKERS]   (S1 exclusive; run from bits/tungsten-robolab, in the background with nohup)
# chain.py log -> out/btl6/<TAG>.log, per-start streaks "seed streak" -> out/btl6/<TAG>.streaks, marker out/btl6/<TAG>.done, pid out/btl6/<TAG>.pid
TAG=$1; CTL=$2; PAR=$3; S0=$4; S1=$5; SECS=$6; OV=${7:-}; W=${8:-6}
echo $$ > out/btl6/$TAG.pid
rm -f out/btl6/$TAG.done
scratchpad/btl5/py scratchpad/btl2/chain.py "$CTL" "$PAR" $S0 $S1 $SECS "$OV" $W > out/btl6/$TAG.log 2>&1
grep -E "^[0-9]+ streak" out/btl6/$TAG.log | awk '{print $1, $3}' > out/btl6/$TAG.streaks
echo "done $(date +%H:%M:%S)" > out/btl6/$TAG.done
