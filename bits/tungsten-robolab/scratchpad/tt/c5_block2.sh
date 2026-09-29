#!/bin/sh
cd /Users/erik/tungsten/bits/tungsten-robolab
while pgrep -f "[m]ixval.sh mix_c5" > /dev/null; do sleep 10; done
scratchpad/tt/mixval.sh mix2_c5 params/myo_tt_p2_r10_c5.txt 720000:720300
