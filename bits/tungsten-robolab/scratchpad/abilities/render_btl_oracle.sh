#!/bin/bash
# Renders the ORACLE-class through-the-legs champion (btl2-b12, params pgP0LRz2) on arena start 715 of dribble_btl_streak_25 (streak 4), with a slow-motion replay.
cd /Users/erik/tungsten/bits/tungsten-robolab
echo "== dribble_btl champion, seed 715"; date
.venv/bin/python playground/tasks/dribble_btl.py --render out/dribble_btl_oracle --params scratchpad/btl2/params/pgP0LRz2.txt \
  --controller bin/challengers/btl2-b12 --seed 715 --body v3 --seconds 15 2>&1 | tail -4 | cut -c1-400
echo "== done"; date
