#!/bin/sh
# forehand ready pitch (wrist flexion) sweep on the champion binary (params only): the retreat-law regime's optimum is a near-vertical face
cd /Users/erik/tungsten/bits/tungsten-robolab
C=bin/champions/tt_p2_300-20260927-194659
P=params/myo_tt_p2_r5_bhprac.txt
S=710000:710120
scratchpad/tt/run_variants.sh v_wf55 $C $P $S "wflex=-0.55"
scratchpad/tt/run_variants.sh v_wf40 $C $P $S "wflex=-0.40"
scratchpad/tt/run_variants.sh v_wf25 $C $P $S "wflex=-0.25"
