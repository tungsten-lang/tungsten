#!/bin/sh
# L7 steering scan batch 2: baseline vs the toe-off predictor on 384 seeds (65001-65384)
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
S=65001-65384
rm -f out/lj7/q_ss2.done
scratchpad/lj7/ss.sh b384 $S "" 6 scratchpad/lj6/params/runner_H011_SB2.txt bin/challengers/long_jump_run_y-l6a
for v in "nat384:j_nat=1" "natw75_384:j_nat=1,j_st_w=0.75" "natn10_384:j_nat=1,j_st_n=10"; do
  name=${v%%:*}; over=${v#*:}
  scratchpad/lj7/ss.sh $name $S "$over" 6 scratchpad/lj6/params/runner_H011_SB2.txt bin/challengers/long_jump_run_y-l7a
done
echo done > out/lj7/q_ss2.done
