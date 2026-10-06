#!/bin/bash
cd /Users/erik/tungsten/bits/tungsten-robolab
scratchpad/btl6/run_set.sh conf_g bin/challengers/btl5-a scratchpad/btl5/params/final_g.txt 81001 81129 15 "" 6
scratchpad/btl6/run_set.sh conf_c1 bin/challengers/btl6-c scratchpad/btl6/params/cand_c1.txt 81001 81129 15 "" 6
echo ALL > out/btl6/conf_runs.done
