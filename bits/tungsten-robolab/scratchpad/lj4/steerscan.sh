#!/bin/sh
# steering scan for the fall-reduced runner F1 on FRESH steering-selection seeds 6001-6128 (never used by L3, S5 or the training / selection / test sets):
# per variant: captures at the penultimate touchdown with the planner settings, summary of the gap and of the starts without a plant flight. L4
# usage: steerscan.sh <seed_a> <seed_b> "<name>:<k=v k=v ...>" ...     (each variant = SB1's settings with the listed overrides)
cd /Users/erik/tungsten/bits/tungsten-robolab
A=$1; B=$2; shift 2
rm -f out/lj4/steerscan.done
for spec in "$@"; do
  name=${spec%%:*}; over=${spec#*:}
  base="j_aim=0.13 j_pl_step=2.81 j_st_w=0.8 j_st_max=0.35 j_st_up=0.35 j_st_n=5 j_st_rnd=0.75"
  .venv/bin/python scratchpad/lj4/mkapp.py scratchpad/lj4/SV_$name.txt $base $over > /dev/null
  scratchpad/lj4/capset.sh scratchpad/lj4/SV_$name.txt sv$name bin/challengers/long_jump_run_y-l4a $A $B 6
  echo "variant $name ($over)" >> out/lj4/steerscan.txt
  .venv/bin/python scratchpad/lj3/gapscan2.py sv$name $A $B 2.83 0.15 --quiet >> out/lj4/steerscan.txt 2>&1
  rm -f out/long_jump_limits/sv${name}_s*
done
echo done > out/lj4/steerscan.done
