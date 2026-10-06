#!/bin/sh
# Q3 (SELECTION 31001-31480; LABELLED beyond-human body, unlimited run-up): (1) identity of the interpolated runner at alpha 1 (chain D keys on the RunGearY controller l4b) against D7 (l3b) on the first 96 seeds;
# (2) the speed / fall frontier: runner alpha 0.5, 0.25, 0.75 with C7's tables; (3) chain D (D7) with the JOINT check-mark shift 0.10 / 0.20.
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
while [ ! -f out/lj6/q1c.done ]; do sleep 5; done
rm -f out/lj6/q3.done
T=long_jump_v4_beyond_robust96
S=31001-31480
L4B=bin/challengers/long_jump_run_y-l4b
L3B=bin/challengers/long_jump_run_x-l3b
scratchpad/lj6/ev6.sh Ra100id $T out/lj6/par_Ra1.txt $L4B 31001-31096 6
scratchpad/lj6/ev6.sh Ra50 $T out/lj6/par_Ra0.5.txt $L4B $S 6
scratchpad/lj6/ev6.sh D7s10 $T out/lj6/par_D7.txt $L3B $S 6 --set "j_board_shift=0.10,ik_gap0=2.761114225899115"
scratchpad/lj6/ev6.sh D7s20 $T out/lj6/par_D7.txt $L3B $S 6 --set "j_board_shift=0.20,ik_gap0=2.661114225899115"
scratchpad/lj6/ev6.sh Ra25 $T out/lj6/par_Ra0.25.txt $L4B $S 6
scratchpad/lj6/ev6.sh Ra75 $T out/lj6/par_Ra0.75.txt $L4B $S 6
echo done > out/lj6/q3.done
