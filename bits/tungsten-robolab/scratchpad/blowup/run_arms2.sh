#!/bin/zsh
# Second driver (replaces the tail of run_arms.sh): after the hold20 lift seed (arena pid given as $1) finishes, the 310 trial with its passing official
# rows primed (prime_310.py; only failing starts run for real), then the hold20 ramp and shc entries, then the official-vs-guarded identity scans.
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
PY=.venv-myo/bin/python
A=scratchpad/blowup/arena_ng.py
LIFT=(--params params/myo_soccer_single_leg_310_lift.txt --controller bin/challengers/soccer5-lift)
RAMP=(--params params/myo_soccer_single_leg_310_ramp.txt --controller bin/challengers/soccer6-i)
SHC=(--params params/myo_soccer_single_leg_310_shc.txt --controller bin/challengers/soccer6-p)
W="--workers 2"
step() { echo "=== $(date '+%m/%d %H:%M:%S') $*"; }
step waiting for pid $1
while kill -0 $1 2>/dev/null; do sleep 5; done
step prime
$PY scratchpad/blowup/prime_310.py
T=soccer_single_leg_310_40_ng
step seed $T lift;  $PY $A seed $T $LIFT --note "round-5 lift (the soccer_single_leg_310_40 champion), MuJoCo wrap-NaN nudged; passing rows primed from the identical official run, failing starts re-run" $=W
step eval $T ramp;  $PY $A eval $T $RAMP --promote --note "round-6 set ramp, MuJoCo wrap-NaN nudged; passing rows primed from the identical official run, failing starts re-run" $=W
step eval $T shc;   $PY $A eval $T $SHC --promote --note "ramp + shift brake, MuJoCo wrap-NaN nudged; passing rows primed from the identical official run, failing starts re-run" $=W
T=soccer_hold20_120_ng
step eval $T ramp;  $PY $A eval $T $RAMP --promote --note "round-6 set ramp (b_t_ramp 0.05) on the lift params" $=W
step eval $T shc;   $PY $A eval $T $SHC --promote --note "ramp + shift capture-point brake (bshc)" $=W
step identity hold20 lift
$PY scratchpad/blowup/identity_scan.py hold20 lift --workers 2
step done
