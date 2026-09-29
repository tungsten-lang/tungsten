#!/bin/sh
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
echo "=== x5a (params/run_gearx_v4_p95_x5a.txt) seeds 251-330"
scratchpad/sprint2/standval.sh params/run_gearx_v4_p95_x5a.txt bin/challengers/run_gearx-a 251 290 4
scratchpad/sprint2/standval.sh params/run_gearx_v4_p95_x5a.txt bin/challengers/run_gearx-a 291 330 4
echo "=== x5c = x5a with g5_a_reach -0.33, seeds 251-330"
scratchpad/sprint2/standval.sh scratchpad/sprint2/x5a_ar-0.33_stand.txt bin/challengers/run_gearx-a 251 290 4
scratchpad/sprint2/standval.sh scratchpad/sprint2/x5a_ar-0.33_stand.txt bin/challengers/run_gearx-a 291 330 4
