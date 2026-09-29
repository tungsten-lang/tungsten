"""Add the two nanguard trials through the arena lock (new keys; no existing trial is touched):

  soccer_single_leg_310_40_ng   the 40 strict 310 s starts of soccer_single_leg_310_40 (seeds 89100-89139, same env and metric bal1_300)
                                under tasks/myo_soccer_ng.py: MuJoCo's tendon-wrap NaN is nudged out of the way instead of ending the hold
  soccer_hold20_120_ng          120 fresh P2 starts (seeds 96000-96119), 20 s episodes, metric hold20 = the kicker is standing since the start and
                                has been on one leg for the last 15 s: certifies early-fall (lift / shift / hold) gains with room for ~15 falls
"""
import json
import sys

sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
import arena

ENV = {"MYO_SOCCER_ENV": "myoChallengeSoccerP2-v0", "MYO_SOCCER_MAX_TIME": "310"}
NG = ("MuJoCo 3.6.0 returns NaN for a tendon whose line grazes its wrapping cylinder (length_circle: acos of a dot product that rounds above 1); "
      "the parked swing leg's right rectus femoris chatters across that tangent and ends about 6 % of the 310 s holds with 'Nan, Inf or huge value in QACC'. "
      "This trial runs tasks/myo_soccer_ng.py (labelled variant nanguard): the stepped MjData advances exactly as MyoSuite's does and is bit-identical to "
      "the official environment until such a NaN, which is nudged out by a <= 1e-6 rad change of the joint angles (nan_events / nan_nudged report the count); "
      "contacts, muscles, reset and scoring are the official ones. ")
NEW = {
    "soccer_single_leg_310_40_ng": {
        "about": NG + "310 s episodes, bal1_300 = 1 when the longest continuous stretch standing on one leg alone reaches 300 s (the other foot below 5 % of "
                 "body weight throughout; the stance foot above 30 %, dropouts up to 0.1 s bridged; counted while the kicker has stayed standing since the start: "
                 "pelvis above 0.7 m, thorax within ~45 deg of vertical). The 40 starts of soccer_single_leg_310_40 (seeds 89100-89139).",
        "env": dict(ENV), "higher": True, "metric": "bal1_300", "python": "myo",
        "report": ["bal1_raw", "bal_l_tot", "bal_r_tot", "stand_time", "fallen", "nan_events", "nan_nudged", "nan_other", "wrap_r_near3", "wrap_r_flips"],
        "seconds": 310, "seeds": list(range(89100, 89140)), "task": "myo_soccer_ng"},
    "soccer_hold20_120_ng": {
        "about": NG + "20 s episodes on 120 fresh P2 resets (seeds 96000-96119, never used by a search, scan or trial): hold20 = 1 when the kicker has stayed "
                 "standing since the start (pelvis above 0.7 m, thorax within ~45 deg of vertical) and the current continuous stretch on one leg alone has "
                 "lasted 15 s at t = 20 s (the lift into single support must be done by 5 s and the hold must not fall), else 0. Room for ~15 falls on the "
                 "round-5 lift champion, so a gain of 5+ starts reaches p < 0.05 where the 300 s trial has only 6 falls to fix.",
        "env": dict(ENV), "higher": True, "metric": "hold20", "python": "myo",
        "report": ["bal1_raw", "stand_time", "fallen", "t_fall", "nan_events", "nan_nudged", "nan_other", "wrap_r_near3", "wrap_r_flips"],
        "seconds": 20, "seeds": list(range(96000, 96120)), "task": "myo_soccer_ng"},
}
with arena.locked():
    trials = arena.load_json(arena.TRIALS, {})
    for name, t in NEW.items():
        if name in trials:
            print(name, "already exists; nothing to do")
            continue
        trials[name] = t
        print("added", name, "with", len(t["seeds"]), "seeds; task", t["task"], "metric", t["metric"], "seconds", t["seconds"])
    arena.save_json(arena.TRIALS, trials)
