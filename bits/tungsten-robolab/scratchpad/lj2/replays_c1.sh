#!/bin/sh
# exactness of build c1 against the stored champion scores (old params, no `gears`)
cd /Users/erik/tungsten/bits/tungsten-robolab
P=.venv/bin/python
C=bin/challengers/long_jump_run-c1
$P scratchpad/lj2/cmp_trial.py long_jump_v4_p95 params/long_jump_v4_p95_ik5.txt $C long_jump_v4_p95b 2
$P scratchpad/lj2/cmp_trial.py long_jump_p95 params/long_jump_p95_ik11.txt $C long_jump_p95e 2
$P scratchpad/lj2/cmp_trial.py long_jump_p95_robust params/long_jump_p95_pn1.txt $C long_jump_p95g 2
$P scratchpad/lj2/cmp_trial.py long_jump_v4_p95_robust params/long_jump_v4_p95_ik2.txt $C long_jump_v4_p95b 2
echo DONE
