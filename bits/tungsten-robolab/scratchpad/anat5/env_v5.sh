# source this: the v5 P95 body (v5.json = v4 + a re-proportioned rectus femoris / hip flexor / vasti split)
export ROBOLAB_BODY=v4
export ROBOLAB_CALIB=v5
export ROBOLAB_PROFILE=p95
export ROBOLAB_PROFILE_PARTS=strength,speed,tendon,activation
unset ROBOLAB_CALIB_SET
cd /Users/erik/tungsten/bits/tungsten-robolab || return 1
