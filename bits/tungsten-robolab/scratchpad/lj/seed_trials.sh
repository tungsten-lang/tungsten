#!/bin/sh
cd /Users/erik/tungsten/bits/tungsten-robolab
.venv/bin/python playground/arena.py seed long_jump_p95_robust32 --params playground/arena/params/long_jump_p95_robust-20260928-052317.txt --controller bin/champions/long_jump_p95_robust-20260928-052317 --task long_jump_p95d --workers 3 --note "baseline: the long_jump_p95_robust champion of 2026-09-28 05:23 unchanged (ideal-control take-off knots ik2d + landing program, check mark 37.53 m), seeded on the 32 fresh starts" 
.venv/bin/python playground/arena.py seed long_jump_elite2_robust32 --params playground/arena/params/long_jump_elite2_robust-20260928-155730.txt --controller bin/champions/long_jump_elite2_robust-20260928-155730 --task long_jump_elite2 --workers 3 --note "baseline: the long_jump_elite2_robust champion of 2026-09-28 15:57 unchanged (elite2 ideal-control take-off knots + landing program, check mark 38.85 m), seeded on the 32 fresh starts"
echo done
