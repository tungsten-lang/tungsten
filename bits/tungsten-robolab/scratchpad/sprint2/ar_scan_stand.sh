#!/bin/sh
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
for a in -0.33 -0.35; do
  echo "=== x5a with g5_a_reach $a"
  scratchpad/sprint2/standval.sh scratchpad/sprint2/x5a_ar${a}_stand.txt bin/challengers/run_gearx-a 221 232 4
  scratchpad/sprint2/standval.sh scratchpad/sprint2/x5a_ar${a}_stand.txt bin/challengers/run_gearx-a 141 180 4
  scratchpad/sprint2/standval.sh scratchpad/sprint2/x5a_ar${a}_stand.txt bin/challengers/run_gearx-a 181 220 4
done
