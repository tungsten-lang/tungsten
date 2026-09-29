"""Add the in-representation batting trials to playground/arena/trials.json (batting round 2, 29 Sep 2026).

    .venv/bin/python scratchpad/bat/make_trials.py

Read-modify-write under the arena lock; never changes an existing trial.
"""
import copy
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "playground"))
import arena  # noqa: E402

SEEDS = list(range(1100, 1124))
ABOUT = ("IN-REPRESENTATION PROGRESS TRIAL (batting round 2): the yardstick for controllers that keep robolab's own "
         "contraction-knot + reflex representation; the open-loop ORACLE programs of bat_power_fresh (reflex gain 0, "
         "25.24 m/s) are ceiling-class and are NOT this trial's reference (its seed entry is the v6 knots swing). "
         "HELD OUT: athlete body, bat_power's metric (sweet-spot bat speed 6 in from the tip at contact, m/s; a miss "
         "scores 0), one pitch per seed drawn continuously (BAT_FRESH_PITCH: speed 34-40.5 m/s, crossing x -0.15..0.15 m "
         "from the plate centre, height 0.62-1.00 m, uniform; bat.py FRESH_*, the distribution of bat_power_fresh) "
         "from NEW seeds 1100-1123 (bat_power_fresh uses 1000-1023), which no swing was trained or tuned on")
NEW = {
    "bat_power_fresh_rep": {
        "about": ABOUT,
        "env": {"BAT_BODY": "athlete", "BAT_FRESH_PITCH": "1"},
        "higher": True,
        "metric": "power",
        "python": "robolab",
        "report": ["flow", "quality", "fair", "hits"],
        "seconds": 7.8,
        "seeds": SEEDS,
        "task": "bat",
    },
}
clean = copy.deepcopy(NEW["bat_power_fresh_rep"])
clean["about"] = ABOUT + "; plus bat_power_clean's hitch-free guard: on every pitch the swing's bat_flow score must be at most 3.0 (flow_ok)"
clean["guard"] = {"flow_ok": True}
NEW["bat_power_fresh_rep_clean"] = clean

with arena.locked():
    trials = arena.load_json(arena.TRIALS, {})
    for k, v in NEW.items():
        if k in trials:
            print(k, "already exists; not touched")
        else:
            trials[k] = v
            print("added", k)
    arena.save_json(arena.TRIALS, trials)
