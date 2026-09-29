#!/bin/sh
# approach-only speed at the check mark, by run-up length, three runners (natural approach: no upright final approach, no steering)
cd /Users/erik/tungsten/bits/tungsten-robolab
C=bin/challengers/long_jump_run-c3
SEEDS=None,401-416
for B in 30 35 40 44 45; do
  for cfg in "runner_p2a.txt:" "lj_runner_gear_v4_p95.txt:g2_v_on=6.5" "lj_runner_gear_v4_p95.txt:g2_v_on=5.0"; do
    f=${cfg%%:*}; o=${cfg#*:}
    P=scratchpad/lj2/$f; [ -f $P ] || P=params/$f
    echo "== board $B runner $f $o"
    .venv/bin/python scratchpad/lj2/runup.py $P $C long_jump_v4_p95b $B $SEEDS "$o" 2 2>&1 | grep -a "SUMMARY\|fell True"
  done
done
echo DONE
