#!/usr/bin/env python3
"""Replay checks of the soccer controller built from a landing commit, run from a clean worktree.

    BIT_HOME=<worktree>/bits <worktree>/bits/tungsten-robolab/.venv-myo/bin/python replay_soccer.py <worktree>

1. the official champion (params/hazard/myo_soccer_310_shc_h2b.txt) on the first 3 seeds of soccer_single_leg_310_40 x 310 s: every numeric
   metric must equal the recorded row of the same start (scratchpad/soccer4/evals/bal1_300-soccer7-bh1-20260929-224305.json);
2. the old brake parameters (bhold off) on 2 starts x 20 s: stand_time / bal1_raw / time must equal Z's identity rows (out/hazard/rows_id1.jsonl).

It is a file with a __main__ guard because arena.evaluate uses multiprocessing 'spawn', which re-imports the main module by path.
"""
import json
import math
import os
import sys

W = os.path.abspath(sys.argv[1]) + "/bits/tungsten-robolab" if len(sys.argv) > 1 else "/Users/erik/rl-verify-0930/bits/tungsten-robolab"
MB = "/Users/erik/tungsten/bits/tungsten-robolab"
sys.path.insert(0, W + "/playground")


def same(a, b):
    if isinstance(a, float) and isinstance(b, float) and math.isnan(a) and math.isnan(b):
        return True
    return a == b


def official():
    import arena
    assert arena.ROOT == W, (arena.ROOT, W)
    trials = json.load(open(W + "/playground/arena/trials.json"))
    t = dict(trials["soccer_single_leg_310_40"])
    t["seeds"] = t["seeds"][:3]
    params = arena.read_params(W + "/params/hazard/myo_soccer_310_shc_h2b.txt")
    rows, scores = arena.evaluate(t, params, W + "/bin/robolab_myo_soccer_v4", "myo_soccer", 3)
    rec = json.load(open(MB + "/scratchpad/soccer4/evals/bal1_300-soccer7-bh1-20260929-224305.json"))["rows"][:3]
    bad = 0
    for s, r, q in zip(t["seeds"], rows, rec):
        keys = [k for k in q if isinstance(q[k], (int, float)) and not isinstance(q[k], bool) and k in r]
        diff = [k for k in keys if not same(r[k], q[k])]
        print("seed", s, "bal1_raw", r.get("bal1_raw"), "recorded", q.get("bal1_raw"), "| numeric keys", len(keys), "differing", diff[:8], flush=True)
        bad += len(diff)
    ok = bad == 0 and all(x == 1.0 for x in scores)
    print("SOCCER OFFICIAL IDENTITY:", "PASS" if ok else "FAIL", "scores", scores, flush=True)
    return ok


def old_params():
    import arena
    params = arena.read_params(W + "/params/myo_soccer_single_leg_310_shc.txt")
    trial = {"python": "myo", "seconds": 20, "env": {"MYO_SOCCER_ENV": "myoChallengeSoccerP2-v0", "MYO_SOCCER_MAX_TIME": "20"}}
    rec = {}
    for line in open(MB + "/out/hazard/rows_id1.jsonl"):
        d = json.loads(line)
        rec[d["tag"]] = d
    bad = 0
    for seed in (97100, 97101):
        r = arena.rollout((trial, params, W + "/bin/robolab_myo_soccer_v4", "myo_soccer_ng", seed))
        q = rec["idB|%d" % seed]
        keys = ("stand_time", "bal1_raw", "time")
        ok = "error" not in r and all(same(float(r.get(k)), float(q.get(k))) for k in keys)
        print("seed", seed, {k: r.get(k) for k in keys}, "recorded", {k: q.get(k) for k in keys}, "fallen", r.get("fallen"), q.get("fallen"), "->", "same" if ok else "DIFFERENT", r.get("error", ""), flush=True)
        bad += 0 if ok else 1
    print("SOCCER OLD-PARAMS IDENTITY:", "PASS" if bad == 0 else "FAIL", flush=True)
    return bad == 0


if __name__ == "__main__":
    a = old_params()      # short first: a failure shows within a minute
    b = official()
    print("REPLAY SOCCER:", "PASS" if a and b else "FAIL", flush=True)
    sys.exit(0 if a and b else 1)
