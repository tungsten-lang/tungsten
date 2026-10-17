#!/bin/bash
# Verify the THIRD landing commit (branch robolab-land-tmp) from a fresh worktree, isolated with BIT_HOME (as verify_1001.sh did for the second commit).
set -uo pipefail
W=/Users/erik/rl-verify-1006
M=/Users/erik/tungsten
B=$W/bits/tungsten-robolab
MB=$M/bits/tungsten-robolab
LOG=$MB/scratchpad/landing/verify_1006.log
exec > "$LOG" 2>&1
echo "== verify $(git -C $W rev-parse --short HEAD) $(date)"
mkdir -p $W/build/cache
[ -e $W/build/cache/compiler-images ] || ln -s $M/build/cache/compiler-images $W/build/cache/compiler-images
for f in tungsten-compiler tungsten-compiler.sidemap tungsten.wc; do [ -e $W/bin/$f ] || ln -s $M/bin/$f $W/bin/$f; done
for v in .venv .venv-myo; do [ -e $B/$v ] || ln -s $MB/$v $B/$v; done
export BIT_HOME=$W/bits
cd $B
export OMP_NUM_THREADS=1 VECLIB_MAXIMUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
echo "== source changes of the commit over main (lib, tasks, tools)"
git -C $W diff --name-status 77b2f0ada HEAD -- bits/tungsten-robolab/lib bits/tungsten-robolab/playground/tasks bits/tungsten-robolab/tools | cut -c1-120
for e in dribble_btl long_jump_run_y run_gearz; do
  echo "== build $e $(date)"; ./build.sh $e 2>&1 | tail -3; echo "exit ${PIPESTATUS[0]}"
done
ls -l bin/robolab_dribble_btl bin/robolab_long_jump_run_y bin/robolab_run_gearz 2>&1 | awk '{print $5, $9}'
echo "== isolation: manifests naming the shared tree (must be none)"; grep -l "/Users/erik/tungsten/bits/tungsten-robolab/lib" $W/build/cache/*.manifest 2>/dev/null | head -3; echo "(end)"
echo "== replays of the champions the commit adds or changes $(date)"
nice -n 10 .venv/bin/python $MB/scratchpad/landing/replay_third.py $W
echo "exit $?"
echo "== py_compile of the new / changed python"; .venv/bin/python -m py_compile playground/tasks/long_jump_v4_beyond_a.py playground/tasks/myo_tt_oracle.py tools/goal_standing.py site/progress/build_progress.py && echo ok
echo "== tools/goal_standing.py runs"; python3 tools/goal_standing.py | tail -2 | cut -c1-200
echo "== handoff paths"; python3 tools/check_doc_paths.py HANDOFF_20260929.md 2>&1 | tail -3
echo "== done $(date)"
