"""Cup search for myo_baoding: hold both balls, centred, for the whole 5 s.

Same environment and skill as myo_baoding, run with every gait amplitude at
zero (the defaults), so each gait state is the cup posture. Scores how long
the balls stay (held fraction) and how well the pair's midpoint stays on the
ellipse centre, where the targets circle. The best cup is the base posture
the finger gait then modulates.
"""

import os

from tasks.myo_baoding import MyoBaodingTask


class MyoBaodingCupTask(MyoBaodingTask):
    name = "myo_baoding_cup"

    def __init__(self):
        root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        self.controller = os.path.join(root, "bin", "robolab_myo_baoding")

    def score(self, metrics):
        held = metrics.get("held_frac", 0.0)
        centred = max(0.0, 1.0 - metrics.get("mid_err", 0.05) / 0.03)
        return held + 0.5 * centred * held + metrics.get("score", 0.0)


TASK = MyoBaodingCupTask
