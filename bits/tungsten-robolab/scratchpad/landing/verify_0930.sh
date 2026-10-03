#!/bin/bash
# Verify the candidate landing commit (branch robolab-land-tmp) from a fresh worktree, isolated with BIT_HOME.
set -uo pipefail
W=/Users/erik/rl-verify-0930
M=/Users/erik/tungsten
B=$W/bits/tungsten-robolab
MB=$M/bits/tungsten-robolab
LOG=$MB/scratchpad/landing/verify_0930.log
exec > "$LOG" 2>&1
echo "== verify $(git -C $W rev-parse --short HEAD) $(date)"
mkdir -p $W/build/cache
[ -e $W/build/cache/compiler-images ] || ln -s $M/build/cache/compiler-images $W/build/cache/compiler-images
for f in tungsten-compiler tungsten-compiler.sidemap tungsten.wc; do [ -e $W/bin/$f ] || ln -s $M/bin/$f $W/bin/$f; done
for v in .venv .venv-myo; do [ -e $B/$v ] || ln -s $MB/$v $B/$v; done
export BIT_HOME=$W/bits
cd $B
echo "== build myo_soccer_v4 $(date)"; ./build.sh myo_soccer_v4 2>&1 | tail -4; echo "exit ${PIPESTATUS[0]}"
echo "== build run_gearx $(date)"; ./build.sh run_gearx 2>&1 | tail -4; echo "exit ${PIPESTATUS[0]}"
ls -l bin/robolab_myo_soccer_v4 bin/robolab_run_gearx 2>&1 | awk '{print $5, $9}'
echo "== isolation: manifests naming the shared tree (must be none)"; grep -l "/Users/erik/tungsten/bits/tungsten-robolab/lib" $W/build/cache/*.manifest 2>/dev/null | head -3; echo "(end)"
echo "== py_compile of the changed python"; .venv/bin/python -m py_compile playground/hsearch.py playground/tt_fast.py playground/tasks/myo_tt_beyond.py playground/tasks/myo_tt_oracle.py site/progress/build_progress.py site/keyframe_bench/seed.py site/keyframe_bench/check_bench.py && echo ok
echo "== soccer: official champion H2b, first 3 seeds x 310 s, against the recorded rows $(date)"
.venv-myo/bin/python - <<'PY'
import sys, json
W = "/Users/erik/rl-verify-0930/bits/tungsten-robolab"; MB = "/Users/erik/tungsten/bits/tungsten-robolab"
sys.path.insert(0, W + "/playground")
import arena
assert arena.ROOT == W, arena.ROOT
trials = json.load(open(W + "/playground/arena/trials.json"))
t = dict(trials["soccer_single_leg_310_40"]); t["seeds"] = t["seeds"][:3]
params = arena.read_params(W + "/params/hazard/myo_soccer_310_shc_h2b.txt")
rows, scores = arena.evaluate(t, params, W + "/bin/robolab_myo_soccer_v4", "myo_soccer", 3)
rec = json.load(open(MB + "/scratchpad/soccer4/evals/bal1_300-soccer7-bh1-20260929-224305.json"))["rows"][:3]
bad = 0
for s, r, q in zip(t["seeds"], rows, rec):
    keys = [k for k in q if isinstance(q[k], (int, float)) and not isinstance(q[k], bool) and k in r]
    diff = [k for k in keys if r[k] != q[k]]
    print("seed", s, "bal1_raw", r.get("bal1_raw"), "recorded", q.get("bal1_raw"), "| numeric keys", len(keys), "differing", diff[:6])
    bad += len(diff)
print("SOCCER OFFICIAL IDENTITY:", "PASS" if bad == 0 and all(x == 1.0 for x in scores) else "FAIL", "scores", scores)
PY
echo "== soccer: the old brake params (bhold off) replay, 2 seeds x 20 s, against Z's identity rows $(date)"
.venv-myo/bin/python - <<'PY'
import sys, json
W = "/Users/erik/rl-verify-0930/bits/tungsten-robolab"; MB = "/Users/erik/tungsten/bits/tungsten-robolab"
sys.path.insert(0, W + "/playground")
import arena
params = arena.read_params(W + "/params/myo_soccer_single_leg_310_shc.txt")
trial = {"python": "myo", "seconds": 20, "env": {"MYO_SOCCER_ENV": "myoChallengeSoccerP2-v0", "MYO_SOCCER_MAX_TIME": "20"}}
rec = {json.loads(l)["tag"]: json.loads(l) for l in open(MB + "/out/hazard/rows_id1.jsonl")}
bad = 0
for seed in (97100, 97101):
    r = arena.rollout((trial, params, W + "/bin/robolab_myo_soccer_v4", "myo_soccer_ng", seed))
    q = rec["idB|%d" % seed]
    ok = all(str(r.get(k)) == str(q.get(k)) or abs(float(r.get(k)) - float(q.get(k))) < 1e-9 for k in ("stand_time", "bal1_raw", "time"))
    print("seed", seed, "bal1_raw", r.get("bal1_raw"), "recorded", q.get("bal1_raw"), "fallen", r.get("fallen"), q.get("fallen"), "->", "same" if ok else "DIFFERENT")
    bad += 0 if ok else 1
print("SOCCER OLD-PARAMS IDENTITY:", "PASS" if bad == 0 else "FAIL")
PY
echo "== sprint: beyond-human champion C, 2 seeds x 30 s and the P95 champion 2 seeds, against the arena records $(date)"
.venv/bin/python - <<'PY'
import sys, json
W = "/Users/erik/rl-verify-0930/bits/tungsten-robolab"; MB = "/Users/erik/tungsten/bits/tungsten-robolab"
sys.path.insert(0, W + "/playground")
import arena
trials = json.load(open(W + "/playground/arena/trials.json")); champs = json.load(open(MB + "/playground/arena/champions.json"))
ctl = W + "/bin/robolab_run_gearx"
bad = 0
for name, pfile in (("sprint_top_speed_v4_beyond", "params/run_gearx_v4_beyond_c.txt"), ("sprint_top_speed_v4_p95", "params/run_gearx_v4_p95_x5a.txt")):
    t = dict(trials[name]); t["seeds"] = t["seeds"][:2]
    rows, scores = arena.evaluate(t, arena.read_params(W + "/" + pfile), ctl, t.get("task", "run_v4"), 2)
    rec = champs[name]["scores"][:2]
    ok = all(abs(a - b) < 1e-9 for a, b in zip(scores, rec))
    print(name, "scores", [round(x, 4) for x in scores], "recorded", [round(x, 4) for x in rec], "->", "same" if ok else "DIFFERENT")
    bad += 0 if ok else 1
print("SPRINT IDENTITY:", "PASS" if bad == 0 else "FAIL")
PY
echo "== table tennis: tt_fast check (default path unchanged) $(date)"
TT_ENV=P2 .venv-myo/bin/python playground/tt_fast.py check 2>&1 | tail -6
echo "== handoff paths"; python3 tools/check_doc_paths.py HANDOFF_20260929.md 2>&1 | tail -2
echo "== done $(date)"
