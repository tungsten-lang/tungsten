#!/bin/bash
# Verify the SECOND landing commit (branch robolab-land-tmp, 77b2f0ada) from a fresh worktree, isolated with BIT_HOME (as verify_0930.sh did for the first commit).
set -uo pipefail
W=/Users/erik/rl-verify-1001
M=/Users/erik/tungsten
B=$W/bits/tungsten-robolab
MB=$M/bits/tungsten-robolab
LOG=$MB/scratchpad/landing/verify_1001.log
exec > "$LOG" 2>&1
echo "== verify $(git -C $W rev-parse --short HEAD) $(date)"
mkdir -p $W/build/cache
[ -e $W/build/cache/compiler-images ] || ln -s $M/build/cache/compiler-images $W/build/cache/compiler-images
for f in tungsten-compiler tungsten-compiler.sidemap tungsten.wc; do [ -e $W/bin/$f ] || ln -s $M/bin/$f $W/bin/$f; done
for v in .venv .venv-myo; do [ -e $B/$v ] || ln -s $MB/$v $B/$v; done
export BIT_HOME=$W/bits
cd $B
echo "== source changes of the commit (second commit over the verified first one): only new files, docs and arena json?"
git -C $W diff --name-status 2cce555da HEAD -- bits/tungsten-robolab/lib bits/tungsten-robolab/playground/tasks bits/tungsten-robolab/playground/hsearch.py | cut -c1-120
for e in run_geary long_jump_run_x long_jump_run_y; do
  echo "== build $e $(date)"; ./build.sh $e 2>&1 | tail -3; echo "exit ${PIPESTATUS[0]}"
done
ls -l bin/robolab_run_geary bin/robolab_long_jump_run_x bin/robolab_long_jump_run_y 2>&1 | awk '{print $5, $9}'
echo "== isolation: manifests naming the shared tree (must be none)"; grep -l "/Users/erik/tungsten/bits/tungsten-robolab/lib" $W/build/cache/*.manifest 2>/dev/null | head -3; echo "(end)"
echo "== replays of the champions the commit adds $(date)"
.venv/bin/python $MB/scratchpad/landing/replay_beyond.py $W
echo "exit $?"
echo "== py_compile of the new python"; .venv/bin/python -m py_compile playground/tasks/long_jump_v4_beyond.py playground/tasks/long_jump_v4_beyond_a.py playground/tasks/sprint_touch_v4y.py playground/tasks/sprint_touch_v4z.py scratchpad/lj3/ljx.py scratchpad/lj4/fresh_check_main.py scratchpad/sprint5/fr.py scratchpad/tt4/plane_probe.py scratchpad/toe/toe_sweep.py && echo ok
echo "== handoff paths"; python3 tools/check_doc_paths.py HANDOFF_20260929.md 2>&1 | tail -3
echo "== done $(date)"
