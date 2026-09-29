"""Prime the rollout cache of soccer_single_leg_310_40_ng with the PASSING rows of O's official (unguarded) runs of the same entries.

Why this is exact: tasks/myo_soccer_ng.py only READS state until a tendon-wrap NaN occurs; a hold that reached 300 s in the official run had no
NaN event before 300 s (a NaN resets the data and the kicker falls within 0.4 s), so the guarded run of that start is bit-identical to the official one
(checked directly: 89101 25 s, 5 more starts, and the official-vs-guarded identity scans in scratchpad/blowup/evals/official-*.json).
Only passing rows are primed; every failing start (the six blow-up starts and the real falls) is re-run for real under the guard.
Each primed cache entry carries "primed_from" (the official evals file); nan_* keys are left absent (unknown for primed rows).

usage: prime_310.py [--dry]"""
import glob
import json
import os
import sys

HERE = "/Users/erik/tungsten/bits/tungsten-robolab"
sys.path.insert(0, os.path.join(HERE, "playground"))
sys.path.insert(0, os.path.join(HERE, "scratchpad", "blowup"))
import arena  # noqa: E402
import arena_ng  # noqa: E402

ENTRIES = {"lift": ("soccer5-lift", "params/myo_soccer_single_leg_310_lift.txt"), "ramp": ("soccer6-i", "params/myo_soccer_single_leg_310_ramp.txt"),
           "shc": ("soccer6-p", "params/myo_soccer_single_leg_310_shc.txt")}
dry = "--dry" in sys.argv
trial = arena.load_json(arena.TRIALS, {})["soccer_single_leg_310_40_ng"]
os.makedirs(arena_ng.CACHE, exist_ok=True)
for arm, (tag, pfile) in ENTRIES.items():
    files = sorted(glob.glob(os.path.join(HERE, "scratchpad", "soccer4", "evals", f"bal1_300-{tag}-*.json")))
    f = files[-1]
    O = json.load(open(f))
    assert O["seeds"] == trial["seeds"], "seed lists differ"
    params = arena.read_params(os.path.join(HERE, pfile))
    ctl = os.path.join(HERE, "bin", "challengers", tag)
    n = 0
    for s, r in zip(O["seeds"], O["rows"]):
        if r.get("bal1_300") != 1.0 or "error" in r:
            continue
        key = arena_ng.rollout_key(trial, params, ctl, "myo_soccer_ng", s)
        path = os.path.join(arena_ng.CACHE, key + ".json")
        row = dict(r)
        row["primed_from"] = os.path.relpath(f, HERE)
        if not dry:
            with open(path, "w") as fh:
                json.dump(row, fh)
        n += 1
    print(f"{arm}: {n} passing official rows primed from {os.path.relpath(f, HERE)}; the other {len(O['seeds']) - n} starts run for real")
