"""Add the 40-start strict-balance trial soccer_single_leg_310_40 through the
arena lock (a new key; no existing trial is touched)."""
import json
import sys

sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
import arena

NAME = "soccer_single_leg_310_40"
with arena.locked():
    trials = arena.load_json(arena.TRIALS, {})
    if NAME in trials:
        print(NAME, "already exists; nothing to do")
        sys.exit(0)
    t = json.loads(json.dumps(trials["soccer_single_leg_310"]))
    t["about"] = (
        "soccer body (290 muscles), fresh phase-2 resets, 310 s episodes (MYO_SOCCER_MAX_TIME; contacts and scoring "
        "untouched) so the hold itself must pass five minutes: bal1_300 = 1 when the longest continuous stretch "
        "standing on one leg alone reaches 300 s (the other foot below 5 % of body weight throughout; the stance foot "
        "above 30 %, dropouts up to 0.1 s bridged; counted while the kicker has stayed standing since the start: pelvis "
        "above 0.7 m, thorax within ~45 deg of vertical), else 0. The same guards and metric as soccer_single_leg_310 "
        "on 40 fixed P2 resets (seeds 89100-89139), disjoint from every practice start and from soccer_single_leg_310's "
        "and soccer_single_leg_300's, so a gain of ~4 stances can reach p < 0.05 (Erik: balance for five minutes on one leg)"
    )
    t["seeds"] = list(range(89100, 89140))
    trials[NAME] = t
    arena.save_json(arena.TRIALS, trials)
    print("added", NAME, "with", len(t["seeds"]), "seeds; env", t["env"], "metric", t["metric"], "seconds", t["seconds"])
