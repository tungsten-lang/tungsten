#!/bin/zsh
# Body sensitivity of the FIXED in-representation controller (batting round 2): the same params on a changed athlete body, 16 fresh pitches
# (seeds 8000-8015, never used for anything else). Each line: calibrated-aim speed (evalcal.py: speed at contact or closest approach, aim
# shift re-centred), as-run hits and power, flow.   scratchpad/bat/bodysweep.sh PARAMS CONTROLLER
cd /Users/erik/tungsten/bits/tungsten-robolab
P=$1; C=$2
S=8000:8016
run() {  # label, env...
  label=$1; shift
  printf "%-28s " "$label"
  env "$@" .venv/bin/python scratchpad/bat/evalcal.py --params $P --controller $C --seeds $S | sed 's/^base *//'
}
run "athlete (1.5 x, vmax 3.0)" BAT_BODY=athlete
run "strength 1.8 (x1.2)" BAT_BODY=athlete BAT_STRENGTH=1.8
run "strength 2.0 (x1.33)" BAT_BODY=athlete BAT_STRENGTH=2.0
run "strength 2.25 (x1.5)" BAT_BODY=athlete BAT_STRENGTH=2.25
run "strength 3.0 (x2)" BAT_BODY=athlete BAT_STRENGTH=3.0
run "vmax 3.6 (x1.2)" BAT_BODY=athlete BAT_VMAX=3.6
run "vmax 4.5 (x1.5)" BAT_BODY=athlete BAT_VMAX=4.5
run "vmax 6.0 (x2)" BAT_BODY=athlete BAT_VMAX=6.0
run "trunk strength x1.5" BAT_BODY=athlete BAT_GROUP_STRENGTH=pelvis_yaw=1.5,spine_=1.5
run "arms strength x1.5" BAT_BODY=athlete BAT_GROUP_STRENGTH=l_shoulder=1.5,r_shoulder=1.5,l_elbow=1.5,r_elbow=1.5,l_wrist=1.5,r_wrist=1.5
run "pelvis yaw strength x2" BAT_BODY=athlete BAT_GROUP_STRENGTH=pelvis_yaw=2.0
run "elbows strength x2" BAT_BODY=athlete BAT_GROUP_STRENGTH=l_elbow=2.0,r_elbow=2.0
run "strength x1.5 + vmax x1.5" BAT_BODY=athlete BAT_STRENGTH=2.25 BAT_VMAX=4.5
