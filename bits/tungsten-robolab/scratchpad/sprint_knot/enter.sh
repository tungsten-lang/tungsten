#!/bin/sh
# enter.sh BODY PARAMS CONTROLLER NOTE   (BODY: avg | p95 | e2)
# held-out check (seeds 51-62, 30 s) on the trial's body, then the arena entry with --promote.
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
BODY=$1; PARAMS=$2; CTL=$3; NOTE=$4
case "$BODY" in
  avg) TRIAL=sprint_top_speed_v4; PROF="";;
  p95) TRIAL=sprint_top_speed_v4_p95; PROF="p95";;
  e2)  TRIAL=sprint_top_speed_v4_elite2; PROF="elite2";;
  *) echo "BODY?"; exit 1;;
esac
if [ -n "$PROF" ]; then export ROBOLAB_PROFILE=$PROF ROBOLAB_PROFILE_PARTS=strength,speed,tendon,activation; fi
export ROBOLAB_CALIB=v4
echo "== held-out (51-62) $TRIAL $PARAMS $CTL"
.venv/bin/python scratchpad/sprint_touch/probe.py run_v4 "$PARAMS" --seconds 30 --seeds 51,52,53,54,55,56,57,58,59,60,61,62 --workers 4 --controller "$CTL" | cut -c1-260
echo "== arena"
.venv/bin/python playground/arena.py eval $TRIAL --task run_v4 --params "$PARAMS" --controller "$CTL" --note "$NOTE" --promote
