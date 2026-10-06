#!/bin/sh
# Q1b (SELECTION 31001-31480, LABELLED beyond-human body, unlimited run-up): the planner-only shifts first (the program sees the shorter gap and responds: off = -0.407 - 1.057 (gap - 2.861)
# and vz +1.04 per m of shorter gap in the harness rows), then the joint shift and chain D with C7's tables.
#  Cn<d>: planner-only: j_board_shift +d (the penultimate toe d closer to the line), ik_gap0 unchanged
#  Cb20 : JOINT shift 0.20 (ik_gap0 - 0.20)
#  D7   : chain D runner + SB2 + R3 + land_C2 with L3's frozen controller long_jump_run_x-l3b
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
while kill -0 73815 2>/dev/null; do sleep 3; done      # the Cb10 evaluation that q1.sh started
rm -f out/lj6/q1b.done
C7=params/long_jump_beyond_rob2.txt
CTL=bin/challengers/long_jump_run_y-l4b
T=long_jump_v4_beyond_robust96
S=31001-31480
for d in 0.10 0.20 0.30; do
  tag=Cn$(echo $d | tr -d '.')
  scratchpad/lj6/ev6.sh $tag $T $C7 $CTL $S 6 --set "j_board_shift=$d"
done
scratchpad/lj6/ev6.sh Cb20 $T $C7 $CTL $S 6 --set "j_board_shift=0.20,ik_gap0=2.661114225899115"
scratchpad/lj6/ev6.sh D7 $T out/lj6/par_D7.txt bin/challengers/long_jump_run_x-l3b $S 6
echo done > out/lj6/q1b.done
