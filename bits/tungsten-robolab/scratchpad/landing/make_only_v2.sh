#!/bin/bash
# Builds scratchpad/landing_only_v2.txt: the `tools/snapshot_commit.sh --only` list of the SECOND landing candidate = the first list
# (scratchpad/landing_only.txt, candidate 2cce555da) + the anatomy study (A5), the subset-keyframe audits and the landing scripts.
# Only a path list: it commits nothing. Run it from anywhere; files that do not exist are skipped.
#
# Left out on purpose: scratchpad/anat5/out (git-ignored), scratchpad/anat5/lit/*.osim and lit/papers (third-party OpenSim model files
# and downloaded papers: sources.json lists them with their URLs), lit/moment_arms_*.json and lit/tree.json (regenerable dumps).
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT=scratchpad/landing_only_v2.txt
cp scratchpad/landing_only.txt "$OUT"
add() { for p in "$@"; do [ -e "$p" ] && echo "$p" >> "$OUT"; done; return 0; }
add playground/calibrations/v5.json playground/calibrations/v5b.json
add scratchpad/anat5/*.py scratchpad/anat5/*.sh scratchpad/anat5/*.md scratchpad/anat5/identity_*.txt scratchpad/anat5/ckpt_*.txt \
    scratchpad/anat5/queue*.txt scratchpad/anat5/queue.log scratchpad/anat5/shared_files_sha256_start.txt \
    scratchpad/anat5/es_*.jsonl scratchpad/anat5/es_*.log scratchpad/anat5/es_*.txt scratchpad/anat5/es_*.npz scratchpad/anat5/params \
    scratchpad/anat5/lit/*.py scratchpad/anat5/lit/sources.json scratchpad/anat5/lit/scenarios.json scratchpad/anat5/lit/tables.txt
add scratchpad/anat5/*.progress
add lib/entry/long_jump_run_y.w lib/robolab/skills/long_jump_run_y.w params/long_jump_beyond_rob2.txt
add lib/entry/run_geary.w lib/robolab/skills/run_geary.w playground/tasks/sprint_touch_v4y.py playground/tasks/sprint_touch_v4z.py params/run_geary_v4_beyond_s5a.txt params/run_geary_v4_beyond_s5b.txt
add lib/entry/long_jump_run_x.w lib/robolab/skills/long_jump_run_x.w playground/tasks/long_jump_v4_beyond.py playground/tasks/long_jump_v4_beyond_a.py \
    params/long_jump_beyond_nom1.txt params/long_jump_beyond_nom2.txt params/long_jump_beyond_nom3_yk.txt params/long_jump_beyond_rob1.txt
add scratchpad/subsets scratchpad/lj3 scratchpad/landing scratchpad/tt4 scratchpad/toe scratchpad/sprint5 scratchpad/lj4
sort -u -o "$OUT" "$OUT"
wc -l "$OUT"
