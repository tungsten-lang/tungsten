#!/bin/sh
cd /Users/erik/tungsten/bits/tungsten-robolab
while pgrep -f "[v]ariants5.sh" > /dev/null; do sleep 10; done
S=90021,90029,90081,90094,90100,90107,90115,90000,90001,90002,90004,90006,90008
for v in "cp_kh=-6" "cp_kh=-4" "cp_kh=-9" "cp_wash=1,cp_kh=-10,cp_khs=4,cp_tau=0.6" "cp_wash=1,cp_kh=-14,cp_khs=4,cp_tau=0.6" "cp_wash=1,cp_kh=-14,cp_khs=10,cp_tau=0.6"; do
  n=$(echo $v | tr '=,' '__')
  .venv-myo/bin/python scratchpad/soccer4/failscan.py --controller bin/challengers/soccer6-e --seeds $S --seconds 20 --workers 3 --set "$v" params/myo_soccer_single_leg_310_lift.txt > scratchpad/soccer4/scan/v6_$n.out 2>&1
done
