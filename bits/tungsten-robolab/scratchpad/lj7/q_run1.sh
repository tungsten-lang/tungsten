#!/bin/sh
# L7 runner fall scan (384 seeds 65001-65384, controller l7a, j_nat 1 + j_st_w 0.75): gear-3 switch speed and F1's g3_k_sps, one at a time
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
while [ ! -f out/lj7/q_ss3.done ]; do sleep 3; done
S=65001-65384
rm -f out/lj7/q_run1.done
B="j_nat=1,j_st_w=0.75"
for v in "g3on92:g3_v_on=9.2" "g3on90:g3_v_on=9.0" "g3on96:g3_v_on=9.6" "sps06:g3_k_sps=-0.06" "g2on74:g2_v_on=7.4" "g2on78:g2_v_on=7.8"; do
  name=${v%%:*}; over=${v#*:}
  scratchpad/lj7/ss.sh r_${name}_384 $S "$B,$over" 6 scratchpad/lj6/params/runner_H011_SB2.txt bin/challengers/long_jump_run_y-l7a
done
echo done > out/lj7/q_run1.done
