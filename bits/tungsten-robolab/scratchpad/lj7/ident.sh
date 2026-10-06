#!/bin/sh
# L7 identity gate: the same params through the frozen reference build (l6a = l4b) and a new build, full jump rollouts on a seed list; every metric of every row must be identical.
# usage: ident.sh <tag> <params> <new_controller> <seeds> [workers]
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
. scratchpad/lj7/env7.sh
tag=$1; params=$2; newc=$3; seeds=$4; w=${5:-6}
for c in ref new; do
  ctl=bin/challengers/long_jump_run_y-l6a; [ $c = new ] && ctl=$newc
  nice -n 10 .venv/bin/python playground/long_jump_eval.py long_jump_v4_beyond_robust96 --params $params --controller $ctl --task long_jump_v4_beyond_a --seeds $seeds --workers $w --out out/lj7/ident_${tag}_${c}.json > out/lj7/ident_${tag}_${c}.txt 2>&1
done
.venv/bin/python - <<PY
import json
a = json.load(open("out/lj7/ident_${tag}_ref.json")); b = json.load(open("out/lj7/ident_${tag}_new.json"))
bad = [(s, k) for s, ra, rb in zip(a["seeds"], a["rows"], b["rows"]) for k in set(ra) | set(rb) if ra.get(k) != rb.get(k)]
print("IDENTITY ${tag}: %d rows, differing (seed, key) pairs: %d %s" % (len(a["rows"]), len(bad), bad[:6]))
PY
