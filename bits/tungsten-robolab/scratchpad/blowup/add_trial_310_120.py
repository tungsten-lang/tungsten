"""Add soccer_single_leg_310_120_ng through the arena lock (a new key): the five-minute one-leg hold on the 120 fresh starts of soccer_hold20_120_ng
(seeds 96000-96119), 310 s episodes, bal1_300, task myo_soccer_ng (the tendon-wrap NaN guard). Room for challengers below the 40 / 40 champion of the
40-start _ng trial, and the champion's five-minute rate on 3x more fresh starts."""
import sys
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
import arena

NAME = "soccer_single_leg_310_120_ng"
with arena.locked():
    trials = arena.load_json(arena.TRIALS, {})
    if NAME in trials:
        print(NAME, "already exists; nothing to do")
        sys.exit(0)
    t = {k: v for k, v in trials["soccer_single_leg_310_40_ng"].items()}
    t["about"] = ("The five-minute one-leg hold (bal1_300 = 1 when the longest continuous stretch on one leg alone reaches 300 s, 310 s episodes) on the 120 fresh P2 starts of "
                  "soccer_hold20_120_ng (seeds 96000-96119, never used by a search, scan or other trial), under tasks/myo_soccer_ng.py (labelled variant nanguard: MuJoCo's tendon-wrap NaN "
                  "is nudged out of the way, bit-identical to the official task until such a NaN; see playground/repros/mujoco_wrap_nan.md). Certifies the hold itself on 3x the starts of "
                  "soccer_single_leg_310_40_ng.")
    t["seeds"] = list(range(96000, 96120))
    trials[NAME] = t
    arena.save_json(arena.TRIALS, trials)
    print("added", NAME, "with", len(t["seeds"]), "seeds; task", t["task"], "metric", t["metric"], "seconds", t["seconds"])
