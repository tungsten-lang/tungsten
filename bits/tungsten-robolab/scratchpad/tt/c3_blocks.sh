#!/bin/sh
# c3 on the two fresh blocks. 3 workers, sequential (r10-n through mixval.sh).
cd /Users/erik/tungsten/bits/tungsten-robolab
scratchpad/tt/mixval.sh mix_c3 params/myo_tt_p2_r10_c3.txt 710000:710600
scratchpad/tt/mixval.sh mix2_c3 params/myo_tt_p2_r10_c3.txt 720000:720300
