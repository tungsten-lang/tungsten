#!/bin/bash
# Third part of the landing verification: the table-tennis default path (tt_fast check needs the built myo_tt entry in the worktree).
set -uo pipefail
W=/Users/erik/rl-verify-0930
MB=/Users/erik/tungsten/bits/tungsten-robolab
B=$W/bits/tungsten-robolab
LOG=$MB/scratchpad/landing/verify_0930c.log
exec > "$LOG" 2>&1
export BIT_HOME=$W/bits
cd $B
echo "== build myo_tt $(date)"; ./build.sh myo_tt 2>&1 | tail -4; echo "exit ${PIPESTATUS[0]}"
ls -l bin/robolab_myo_tt 2>&1 | awk '{print $5, $9}'
echo "== tt_fast check (TT_ENV=P2) $(date)"
TT_ENV=P2 .venv-myo/bin/python playground/tt_fast.py check 2>&1 | grep -v -i "warn\|logger" | tail -12
echo "exit ${PIPESTATUS[0]}"
echo "== done $(date)"
