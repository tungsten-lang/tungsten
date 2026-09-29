#!/bin/sh
# after a robust stage: assemble the take-off params, take the hand-overs of the training starts (+2 execution-noise variants each)
# and record the chunk landing of the nominal start (the landing search's x0). usage: post_robust.sh <f3|am> [ik_fmin]
cd /Users/erik/tungsten/bits/tungsten-robolab
X=$1; FMIN=${2:-}
export ROBOLAB_CALIB=v4 ROBOLAB_PROFILE=p95 ROBOLAB_PROFILE_PARTS=strength,speed,tendon,activation ROBOLAB_LJ_APPROACH=44
case $X in f3) A=scratchpad/lj2/A3.txt;; am) A=scratchpad/lj2/A2_m495.txt;; a4) A=scratchpad/lj2/A4.txt;; esac
TR=$(cat scratchpad/lj2/${X}_train.txt | tr -d '\n')
OV=""; [ -n "$FMIN" ] && OV="ik_fmin=$FMIN"
.venv/bin/python scratchpad/lj2/assemble.py params/long_jump_v4_gear_${X}_r1.txt $A out/long_jump_limits/rob_${X}.txt $OV
.venv/bin/python playground/long_jump_limits.py handover params/long_jump_v4_gear_${X}_r1.txt --captures $TR --name ho${X}r --variants ${VARIANTS:-2} > out/long_jump_limits/ho_${X}r.log 2>&1
.venv/bin/python playground/long_jump_limits.py record long_jump_v4_p95b --params params/long_jump_v4_gear_${X}_r1.txt --controller bin/challengers/long_jump_run-c3 ${RECSEED:+--seed $RECSEED} --name rec${X} > out/long_jump_limits/rec_${X}.log 2>&1
echo done > out/long_jump_limits/post_robust_${X}.done
