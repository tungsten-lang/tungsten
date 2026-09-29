"""Grasp lab for myo_relocate: the same environment with a 3 s limit, to test
whether a grasp holds when it is not rushed (slow, precise parameters). Not
an official task: it separates "cannot grasp" from "cannot grasp in 1.5 s".
Reports max_held_z (object height while within 10 cm of the palm) and
`lifted` (held above 1.0 m).
"""

import os

from tasks.myo_relocate import MyoRelocateTask


class MyoRelocateGlabTask(MyoRelocateTask):
    name = "myo_relocate_glab"
    env_kwargs = {"max_episode_steps": 300}

    def __init__(self):
        root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        self.controller = os.path.join(root, "bin", "robolab_myo_relocate")

    def metrics(self, sim, log):
        out = super().metrics(sim, log)
        out["lifted"] = float(out.get("max_held_z", 0.9) > 1.0)
        return out

    def score(self, metrics):
        return metrics.get("lifted", 0.0) + min(1.0, max(0.0, metrics.get("max_held_z", 0.9) - 0.91) / 0.2)


TASK = MyoRelocateGlabTask
