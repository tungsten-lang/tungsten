#!/bin/sh
cd /Users/erik/tungsten/bits/tungsten-robolab
S=90021,90029,90081,90094,90100,90107,90115,90035,90036,90041,90085,90003,90005,90007
for v in "bretry=1,bcout=1,bc_out=0.04,bc_retry=2,bc_short=20,bc_arm=12" "bretry=1,bcout=1,bc_out=0.03,bc_retry=2,bc_short=20,bc_arm=12" "bretry=1,bc_retry=2,bc_short=20"; do
  n=$(echo $v | tr '=,' '__' | cut -c1-60)
  .venv-myo/bin/python scratchpad/soccer4/failscan.py --controller bin/challengers/soccer6-d --seeds $S --seconds 20 --workers 3 --set "$v" params/myo_soccer_single_leg_310_lift.txt > scratchpad/soccer4/scan/v5_$n.out 2>&1
done
