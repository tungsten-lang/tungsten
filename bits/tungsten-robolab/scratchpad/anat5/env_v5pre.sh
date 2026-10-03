# source this: the PRELIMINARY v5 (the split as specified in the brief, through ROBOLAB_CALIB_SET; no calibration file needed)
export ROBOLAB_BODY=v4
export ROBOLAB_CALIB=v4
export ROBOLAB_CALIB_SET='peaks={"hip_flex_pos":190,"rf":60,"knee_neg":302}'
export ROBOLAB_PROFILE=p95
export ROBOLAB_PROFILE_PARTS=strength,speed,tendon,activation
cd /Users/erik/tungsten/bits/tungsten-robolab || return 1
