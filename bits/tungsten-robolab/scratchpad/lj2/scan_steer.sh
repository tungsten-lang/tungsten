#!/bin/sh
# steering scan: falls/no-take-off and penultimate gap spread on 96 training seeds (L2)
cd /Users/erik/tungsten/bits/tungsten-robolab
for cfg in "j_st_w=0.6,j_st_max=0.3,j_st_n=6" "j_st_w=0.5,j_st_max=0.25,j_st_n=5" "j_st_w=0.8,j_st_max=0.2,j_st_n=4" "j_st_w=1.0,j_st_max=0.15,j_st_n=6" "j_st_w=0.3,j_st_max=0.3,j_st_n=6"; do
  echo "== $cfg"
  .venv/bin/python scratchpad/lj2/ikgap.py long_jump_v4_p95_robust32 long_jump_v4_p95b bin/challengers/long_jump_run-c1 scratchpad/lj2/A1ik.txt 8001-8096 "$cfg" 2 2>&1 | tail -2
done
echo DONE
