"""MyoChallenge 2023 Relocate, phase-2 evaluation environment
(myoChallengeRelocateP2eval-v0): wider object ranges (x -0.2..0.15 and
y -0.4..-0.1 around the table origin, geoms up to 3.5 cm, 50-300 g) and more
initial joint noise than P2 (not random in MyoSuite 2.12.2: every episode
starts at init_qpos + 0.015 x each joint's range, P2 0.01). Same skill,
controller, sensors and scoring as myo_relocate: the goal is fixed at
(0, -0.25, 0.9), while the physical receptacle stands invisible at the
randomised target pose, here anywhere over x -0.5..0.4, y -0.5..-0.1 (see
myo_relocate and tasks/myo_relocate_v6.py).
"""

import os

from tasks.myo_relocate import MyoRelocateTask


class MyoRelocateEvalTask(MyoRelocateTask):
    name = "myo_relocate_eval"
    env_id = "myoChallengeRelocateP2eval-v0"

    def __init__(self):
        root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        self.controller = os.path.join(root, "bin", "robolab_myo_relocate")


TASK = MyoRelocateEvalTask
