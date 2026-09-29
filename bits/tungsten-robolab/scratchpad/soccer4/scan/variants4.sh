#!/bin/sh
cd /Users/erik/tungsten/bits/tungsten-robolab
while pgrep -f "[v]ariants3.sh" > /dev/null; do sleep 10; done
S=89110,89115,89117,89130,89133,89100,89101,89102,89103,89104
for v in "bgset=1,b_g_set=1.5" "bgset=1,b_g_set=2.0" "bramp=1,b_t_ramp=0.2" "bramp=1,b_t_ramp=0.45"; do
  n=$(echo $v | tr '=,' '__')
  .venv-myo/bin/python scratchpad/soccer4/failscan.py --controller bin/challengers/soccer6-b --seeds $S --seconds 20 --workers 3 --set "$v" params/myo_soccer_single_leg_310_lift.txt > scratchpad/soccer4/scan/v4_$n.out 2>&1
done
