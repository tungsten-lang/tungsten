#!/bin/sh
# final-approach scan for F1 + SB2 (the pen-state's trunk): captures of seeds 6001-6256 per variant, then the harness statistics of L3's r3 take-off on them. L4
# usage: finscan.sh "<name>:<k=v ...>" ...
cd /Users/erik/tungsten/bits/tungsten-robolab
. scratchpad/lj4/env.sh
export ROBOLAB_LJ_APPROACH=151.025 ROBOLAB_LJ_MARGIN=0.03
rm -f out/lj4/finscan.done
for spec in "$@"; do
  name=${spec%%:*}; over=${spec#*:}
  base="j_aim=0.13 j_pl_step=2.75 j_st_w=0.8 j_st_max=0.35 j_st_up=0.35 j_st_n=7 j_st_rnd=0.5"
  .venv/bin/python scratchpad/lj4/mkapp.py scratchpad/lj4/FS_$name.txt $base $over > /dev/null
  scratchpad/lj4/capset.sh scratchpad/lj4/FS_$name.txt fs$name bin/challengers/long_jump_run_y-l4a 6001 6256 6
  echo "variant $name ($over)" >> out/lj4/finscan.txt
  .venv/bin/python scratchpad/lj3/gapscan2.py fs$name 6001 6256 2.83 0.15 --quiet >> out/lj4/finscan.txt 2>&1
  nice -n 10 .venv/bin/python scratchpad/lj4/capstat.py out/lj3/rob_r3_snap.txt fs$name 6001 6256 1.5 >> out/lj4/finscan.txt 2>&1
  rm -f out/long_jump_limits/fs${name}_s*
done
echo done > out/lj4/finscan.done
