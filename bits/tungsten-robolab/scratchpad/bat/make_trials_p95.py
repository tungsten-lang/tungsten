"""Add the labelled P95-body batting trial (batting round 2, 29 Sep 2026). Read-modify-write under the arena lock; never changes an existing trial.

    .venv/bin/python scratchpad/bat/make_trials_p95.py
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "playground"))
import arena  # noqa: E402

NEW = {
    "bat_power_fresh_rep_p95": {
        "about": ("LABELLED BODY VARIANT, never to be compared with the athlete-body trials: the athlete body (strength x1.5, vmax 3.0) at the "
                  "95th-percentile muscle profile (ROBOLAB_PROFILE=p95: peak force x1.32, maximum shortening velocity x1.2, activation and "
                  "deactivation constants x0.87; playground/profiles/p95.json, each a marginal P95 of healthy young men from the sources listed "
                  "there, so a composite that a real person rarely matches on every part; the athlete's own x1.5 strength already stands for "
                  "strength-trained men), i.e. a top-5% athlete. Everything else is bat_power_fresh_rep: in-representation swings (contraction knots, "
                  "reflexes on), sweet-spot bat speed at contact (m/s, a miss scores 0), 24 fresh continuous pitches (BAT_FRESH_PITCH) from the "
                  "seeds 1100-1123 that no swing was trained or tuned on"),
        "env": {"BAT_BODY": "athlete", "BAT_FRESH_PITCH": "1", "ROBOLAB_PROFILE": "p95"},
        "higher": True,
        "metric": "power",
        "python": "robolab",
        "report": ["flow", "quality", "fair", "hits"],
        "seconds": 7.8,
        "seeds": list(range(1100, 1124)),
        "task": "bat",
    },
}
with arena.locked():
    trials = arena.load_json(arena.TRIALS, {})
    for k, v in NEW.items():
        if k in trials:
            print(k, "already exists; not touched")
        else:
            trials[k] = v
            print("added", k)
    arena.save_json(arena.TRIALS, trials)
