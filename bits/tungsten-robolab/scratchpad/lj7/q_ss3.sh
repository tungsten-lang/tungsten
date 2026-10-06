#!/bin/sh
# L7 steering scan batch 3 (384 seeds 65001-65384, controller l7a, runner H011 + SB2 + j_nat 1): w 0.75 / 0.7 with n 10, caps 0.5
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
while [ ! -f out/lj7/q_sel1.done ]; do sleep 3; done
S=65001-65384
rm -f out/lj7/q_ss3.done
for v in "w75n10:j_nat=1,j_st_w=0.75,j_st_n=10" "w75n10c50:j_nat=1,j_st_w=0.75,j_st_n=10,j_st_max=0.5,j_st_up=0.5" "w70n10:j_nat=1,j_st_w=0.7,j_st_n=10" "w75n12:j_nat=1,j_st_w=0.75,j_st_n=12"; do
  name=${v%%:*}; over=${v#*:}
  scratchpad/lj7/ss.sh ${name}_384 $S "$over" 6 scratchpad/lj6/params/runner_H011_SB2.txt bin/challengers/long_jump_run_y-l7a
done
echo done > out/lj7/q_ss3.done
