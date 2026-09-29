#!/bin/sh
cd /Users/erik/tungsten/bits/tungsten-robolab
S=89110,89115,89117,89130,89133,89100,89101,89102,89103,89104
for v in "bramp=1,b_t_ramp=0.8" "bramp=1,b_t_ramp=1.2" "bfore=1,b_fx_tol=0.06" "cp_more=1,cp_ksw=3,cp_klb=3" "cp_more=1,cp_klb=4,cp_kh=-6" "bramp=1,b_t_ramp=0.8,cp_kh=-6"; do
  n=$(echo $v | tr '=,' '__')
  .venv-myo/bin/python scratchpad/soccer4/failscan.py --controller bin/challengers/soccer6-a --seeds $S --seconds 20 --workers 3 --set "$v" params/myo_soccer_single_leg_310_lift.txt > scratchpad/soccer4/scan/v3_$n.out 2>&1
done
