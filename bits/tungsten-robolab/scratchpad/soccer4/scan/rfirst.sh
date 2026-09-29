#!/bin/sh
cd /Users/erik/tungsten/bits/tungsten-robolab
while pgrep -f "[t]rain_lift.json" > /dev/null; do sleep 10; done
.venv-myo/bin/python scratchpad/soccer4/failscan.py --controller bin/challengers/soccer6-b --seeds 90000:90040 --seconds 12 --workers 4 --set bc_first=1 --json scratchpad/soccer4/scan/train_rfirst.json params/myo_soccer_single_leg_310_lift.txt > scratchpad/soccer4/scan/train_rfirst.out 2>&1
