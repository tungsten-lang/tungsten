#!/bin/sh
# The final noise ladder (full rollouts, official metrics) and the official soccer_p2 reset (seeds 5000-5099): the phase-1 champion vs MyoKickSkill with kr.
cd /Users/erik/tungsten/bits/tungsten-robolab
exec .venv-myo/bin/python scratchpad/kick/kltable.py \
  --entry "champion:bin/champions/soccer_p1-20260926-151503:playground/arena/params/soccer_p1-20260926-151503.txt" \
  --entry "kr:bin/challengers/kick-a8:params/myo_kick_kr0.txt" \
  --seeds 6000:6012 --rungs 0,0.05,0.1,0.25,0.5 --offsets=-0.05:0,-0.1:0,0:0.1,0:-0.1 --official 5000:5100 --json scratchpad/kick/out/ladder_final.json
