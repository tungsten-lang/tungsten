"""Partial results of an arena_cached evaluation: evalstatus.py <trial> <params> <controller>"""
import json, os, sys
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/soccer4")
import arena
import arena_cached as ac
trial = json.load(open(arena.TRIALS))[sys.argv[1]]
params = arena.read_params(sys.argv[2]); ctl = os.path.abspath(sys.argv[3])
done = []
for s in trial["seeds"]:
    p = os.path.join(ac.CACHE, ac.rollout_key(trial, params, ctl, trial["task"], s) + ".json")
    if os.path.exists(p):
        r = json.load(open(p)); done.append((s, r.get("bal1_raw"), r.get("bal1_300"), r.get("stand_time"), r.get("fallen")))
ok = sum(1 for d in done if d[2] == 1.0)
print(f"{len(done)}/{len(trial['seeds'])} done, {ok} hold 300 s")
for d in done: print("  ", d)
