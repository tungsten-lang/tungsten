#!/bin/sh
# accelerated blow-up test: 12 starts x 60 s per arm at three levels of swing-ankle chatter (kd_leg 0.2: rms 83, base: 62, k_leg 22: 7)
cd /Users/erik/tungsten/bits/tungsten-robolab
for arm in "kd_leg=0.2" "base" "k_leg=22"; do
  set_arg=""; [ "$arm" != "base" ] && set_arg="--set $arm"
  nice -n 5 .venv-myo/bin/python scratchpad/soccer4/failscan.py --controller bin/challengers/soccer6-p --seeds 91000:91012 --seconds 60 --workers 4 $set_arg \
    --json scratchpad/soccer4/scan/stress_$arm.json params/myo_soccer_single_leg_310_shc.txt > scratchpad/soccer4/scan/stress_$arm.out 2>&1
done
