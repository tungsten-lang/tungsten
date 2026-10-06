#!/bin/bash
cd /Users/erik/tungsten/bits/tungsten-robolab
for t in dribble_btl_streak_fresh32 dribble_btl_streak_25 dribble_btl_25 dribble_btl; do
  scratchpad/btl6/py playground/arena.py eval $t --params scratchpad/btl6/params/final_i.txt --controller bin/challengers/btl6-final --task dribble_btl_v3 --workers 6 --promote --note "D5 round 6: G + stage-3 apex-hinge block (btl6-final + final_i.txt, ORACLE-class)" > out/btl6/arena_$t.log 2>&1
done
echo ALL > out/btl6/arena_runs.done
