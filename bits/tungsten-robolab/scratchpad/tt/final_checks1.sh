#!/bin/sh
# After the arena run of c1: a second independent block of fresh serves, tt_p1 (no regression) and tt_p2_backhand (reported, not promoted). 3 workers, sequential.
cd /Users/erik/tungsten/bits/tungsten-robolab
scratchpad/tt/mixval.sh mix2_c1 params/myo_tt_p2_r10_c1.txt 720000:720300
B=/Users/erik/tungsten/bits/tungsten-robolab/bin/challengers/myo_tt_r10-n
.venv-myo/bin/python playground/arena.py eval tt_p1 --params params/myo_tt.txt --controller $B --note "round 10 build, P1 params: no-regression check" > out/tt_r10/arena_tt_p1_r10n.log 2>&1
.venv-myo/bin/python playground/arena.py eval tt_p2_backhand --params params/myo_tt_p2_r10_c1.txt --controller $B --note "round 10 c1 (reported, not promoted)" > out/tt_r10/arena_tt_p2_backhand_c1.log 2>&1
