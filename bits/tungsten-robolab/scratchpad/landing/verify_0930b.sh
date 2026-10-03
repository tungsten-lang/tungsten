#!/bin/bash
# Second half of the landing verification (the builds passed in verify_0930.sh): replays from the clean worktree, as guarded .py files.
set -uo pipefail
W=/Users/erik/rl-verify-0930
M=/Users/erik/tungsten
B=$W/bits/tungsten-robolab
MB=$M/bits/tungsten-robolab
LOG=$MB/scratchpad/landing/verify_0930b.log
exec > "$LOG" 2>&1
echo "== verify (replays) $(git -C $W rev-parse --short HEAD) $(date)"
export BIT_HOME=$W/bits
cd $B
echo "== py_compile of the changed python"; .venv/bin/python -m py_compile playground/hsearch.py playground/tt_fast.py playground/tasks/myo_tt_beyond.py playground/tasks/myo_tt_oracle.py site/progress/build_progress.py site/keyframe_bench/seed.py site/keyframe_bench/check_bench.py && echo ok
echo "== sprint replays $(date)"
.venv/bin/python $MB/scratchpad/landing/replay_sprint.py $W
echo "exit $?"
echo "== soccer replays $(date)"
.venv-myo/bin/python $MB/scratchpad/landing/replay_soccer.py $W
echo "exit $?"
echo "== table tennis: tt_fast check (default path unchanged) $(date)"
TT_ENV=P2 .venv-myo/bin/python playground/tt_fast.py check 2>&1 | tail -6
echo "== handoff paths"; python3 tools/check_doc_paths.py HANDOFF_20260929.md 2>&1 | tail -2
echo "== done $(date)"
