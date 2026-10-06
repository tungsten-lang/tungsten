#!/bin/bash
# gate_scan.sh: closed-loop scans of the energy gates on the 840 training seeds (6 s), one after the other
cd /Users/erik/tungsten/bits/tungsten-robolab
for cfg in "g3a pg_gv3=0.15" "g3b pg_gv3=0.25" "g3c pg_gv3=0.4" "g2a pg_gv2=0.3" "g2b pg_gv2=0.6"; do
  set -- $cfg
  scratchpad/btl6/run_set.sh cl_$1 bin/challengers/btl6-b scratchpad/btl5/params/final_g.txt 84001 84841 6 "$2" 6
done
echo ALL > out/btl6/gate_scan.done
