#!/bin/sh
# c2 (backhand of run 21, forehand = champion) on the two fresh blocks. 3 workers, sequential.
cd /Users/erik/tungsten/bits/tungsten-robolab
scratchpad/tt/mixval.sh mix_c2 params/myo_tt_p2_r10_c2.txt 710000:710600
scratchpad/tt/mixval.sh mix2_c2 params/myo_tt_p2_r10_c2.txt 720000:720300
