#!/bin/sh
# L7: pool captures with the chosen steering (approach_nat_w75.txt = H011 + SB2 + j_nat 1 + j_st_w 0.75; controller l7a): pool A = training seeds 64001-65000, pool H = held-out surrogate seeds 66001-66500
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
while [ ! -f out/lj7/q_conf1.done ]; do sleep 3; done
. scratchpad/lj7/env7.sh
export ROBOLAB_LJ_APPROACH=151.025 ROBOLAB_LJ_MARGIN=0.03
rm -f out/lj7/q_cap1.done
A=scratchpad/lj7/params/approach_nat_w75.txt
C=bin/challengers/long_jump_run_y-l7a
scratchpad/lj7/capset7.sh $A pa $C 64001 65000 6
.venv/bin/python scratchpad/lj4/mklist.py pa 64001 65000 out/lj7/pa 2 1 > out/lj7/pa_list.log 2>&1
scratchpad/lj7/capset7.sh $A ph $C 66001 66500 6
.venv/bin/python scratchpad/lj4/mklist.py ph 66001 66500 out/lj7/ph 2 1 > out/lj7/ph_list.log 2>&1
echo done > out/lj7/q_cap1.done
