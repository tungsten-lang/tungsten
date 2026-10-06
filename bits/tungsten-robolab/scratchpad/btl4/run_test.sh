#!/bin/sh
# usage: run_test.sh TAG S0 S1 CAND_CTL CAND_PARAMS   (runs baseline btl3-e + final_e.txt and the candidate, 15 s, 6 workers, once each)
TAG=$1; S0=$2; S1=$3; CTL=$4; PAR=$5
cd /Users/erik/tungsten/bits/tungsten-robolab
export OMP_NUM_THREADS=1
nice -n 10 .venv/bin/python scratchpad/btl2/chain.py bin/challengers/btl3-e scratchpad/btl3/params/final_e.txt $S0 $S1 15 "" 6 > out/btl4/test_${TAG}_base.log 2>&1
nice -n 10 .venv/bin/python scratchpad/btl2/chain.py $CTL $PAR $S0 $S1 15 "" 6 > out/btl4/test_${TAG}_cand.log 2>&1
grep -E "^[0-9]+ streak" out/btl4/test_${TAG}_base.log | awk '{print $1, $3}' > out/btl4/test_${TAG}_base.streaks
grep -E "^[0-9]+ streak" out/btl4/test_${TAG}_cand.log | awk '{print $1, $3}' > out/btl4/test_${TAG}_cand.streaks
echo done > out/btl4/test_${TAG}.done
