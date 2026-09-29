#!/bin/zsh
# Third driver: after run_arms2.sh (pid $1) finishes (its last step is the official-vs-guarded identity scan of the hold20 lift entry):
# the REAL guarded 310 s runs of the passing starts of the brake and lift entries (unbiased telemetry, identity at scale), then the 310 s identity sample.
# NOTE: this wrapper was stopped after full310 shc had started (see LOG.md 11:25); full310 lift did not run.
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
PY=.venv-myo/bin/python
step() { echo "=== $(date '+%m/%d %H:%M:%S') $*"; }
step waiting for pid $1
while kill -0 $1 2>/dev/null; do sleep 5; done
step full310 shc;           $PY scratchpad/blowup/full310.py shc --workers 2
step full310 lift;          $PY scratchpad/blowup/full310.py lift --workers 2
step done
