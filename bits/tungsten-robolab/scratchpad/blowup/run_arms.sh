#!/bin/zsh
# Sequential arena runs of the three balance entries on the two nanguard trials (2 rollout workers at a time). Rollouts are cached
# (scratchpad/blowup/evalcache), so a killed run resumes with the same command. Challengers run with --promote in chronological order
# (lift, ramp, brake): a win over the current champion at p < 0.05 promotes, as in any arena run.
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
PY=.venv-myo/bin/python
A=scratchpad/blowup/arena_ng.py
LIFT=(--params params/myo_soccer_single_leg_310_lift.txt --controller bin/challengers/soccer5-lift)
RAMP=(--params params/myo_soccer_single_leg_310_ramp.txt --controller bin/challengers/soccer6-i)
SHC=(--params params/myo_soccer_single_leg_310_shc.txt --controller bin/challengers/soccer6-p)
W="--workers 2"
step() { echo "=== $(date '+%m/%d %H:%M:%S') $*"; }
T=soccer_hold20_120_ng
step seed $T lift;  $PY $A seed $T $LIFT --note "round-5 lift (the soccer_single_leg_310_40 champion): the cp4 hold with the lift into single support tuned" $=W
step eval $T ramp;  $PY $A eval $T $RAMP --promote --note "round-6 set ramp (b_t_ramp 0.05) on the lift params" $=W
step eval $T shc;   $PY $A eval $T $SHC --promote --note "ramp + shift capture-point brake (bshc)" $=W
T=soccer_single_leg_310_40_ng
step seed $T lift;  $PY $A seed $T $LIFT --note "round-5 lift (the soccer_single_leg_310_40 champion), MuJoCo wrap-NaN nudged" $=W
step eval $T ramp;  $PY $A eval $T $RAMP --promote --note "round-6 set ramp, MuJoCo wrap-NaN nudged" $=W
step eval $T shc;   $PY $A eval $T $SHC --promote --note "ramp + shift brake, MuJoCo wrap-NaN nudged" $=W
step done
