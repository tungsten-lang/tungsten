#!/bin/sh
cd /Users/erik/tungsten/bits/tungsten-robolab
# wait for variants1 to finish
while pgrep -f "[v]ariants1.sh" > /dev/null; do sleep 10; done
S=89110,89115,89117,89130,89133,89100,89101,89102,89103,89104
for v in "tl_kp=0" "tl_kp=10" "tl_wfoot=1.0" "tl_kp=0,tl_kd=0"; do
  n=$(echo $v | tr '=,' '__')
  .venv-myo/bin/python scratchpad/soccer4/failscan.py --controller bin/challengers/soccer5-lift --seeds $S --seconds 20 --workers 3 --set "$v" params/myo_soccer_single_leg_310_lift.txt > scratchpad/soccer4/scan/v2_$n.out 2>&1
done
