"""Gait search for myo_baoding: turn the pair of balls one way, fast, without
dropping them (param `spin` = 1 counter-clockwise gait `a`, -1 clockwise
gait `b`; the skill then runs the gait without pacing).

Scores the pair's signed rotation over the 5 s (turns in the gait's
direction), the held fraction, and how well the pair's midpoint stays on the
ellipse centre. The best gaits become the actuators the full task paces
against its targets.
"""

import os

from tasks.myo_baoding import MyoBaodingTask


class MyoBaodingSpinTask(MyoBaodingTask):
    name = "myo_baoding_spin"
    env_kwargs = {"max_episode_steps": 120}  # 3 s: enough to measure the turning rate

    def __init__(self):
        root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        self.controller = os.path.join(root, "bin", "robolab_myo_baoding")

    def metrics(self, sim, log):
        out = super().metrics(sim, log)
        out["spin"] = float(sim.params.get("spin", 1.0))
        return out

    def horizon(self, sim):
        return self.env_kwargs["max_episode_steps"]

    def score(self, metrics):
        # holding first; turning counts in proportion to held^4, so turning
        # the pair while dropping it (the balls roll off) is worth little
        held = metrics.get("held_frac", 0.0)
        turns = metrics.get("turn", 0.0) * metrics.get("spin", 1.0)
        centred = max(0.0, 1.0 - metrics.get("mid_err", 0.05) / 0.03)
        return held + 2.0 * turns * held ** 4 + 0.3 * centred * held


TASK = MyoBaodingSpinTask
