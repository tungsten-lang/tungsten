#!/bin/zsh
# queue1.sh: after the margin design (pid in out/hazard/grid1.pid) ends, run the push calibration on ONE worker (the 4th of the 4 allowed while the fresh scan uses 3)
cd /Users/erik/tungsten/bits/tungsten-robolab
while kill -0 $(cat out/hazard/grid1.pid) 2>/dev/null; do sleep 3; done
.venv-myo/bin/python scratchpad/hazard/wscan2.py --jobs out/hazard/jobs_pushcal.json --out out/hazard/rows_pushcal.jsonl --workers 1 --mode 0 > out/hazard/pushcal.log 2>&1
