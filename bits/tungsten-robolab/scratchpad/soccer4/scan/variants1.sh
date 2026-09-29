#!/bin/sh
# quick sign/ablation experiments on the five failing seeds of the lift challenger + 5 passing controls
cd /Users/erik/tungsten/bits/tungsten-robolab
S=89110,89115,89117,89130,89133,89100,89101,89102,89103,89104
for v in "cp_kh=0" "cp_kh=-6" "sb_kha=4.0" "cp_kh=6"; do
  n=$(echo $v | tr '=,' '__')
  .venv-myo/bin/python scratchpad/soccer4/failscan.py --controller bin/challengers/soccer5-lift --seeds $S --seconds 20 --workers 3 --set "$v" params/myo_soccer_single_leg_310_lift.txt > scratchpad/soccer4/scan/v1_$n.out 2>&1
done
