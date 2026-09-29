"""Sprint from starting blocks (tasks/sprint_blocks.py: same blocks, rules,
metrics and Bolt reference) on the v3 body with the 95th-percentile adult
profile (playground/profiles/p95.json via body_profile.py: strength x1.32,
muscle speed x1.2, tendon stiffness x1.5, activation time constants x0.87;
the skeleton's anthropometry unchanged). Same as ROBOLAB_PROFILE=p95 on the
default task, named so the arena records it."""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # run as a script too
from body import HumanoidV2Builder, HumanoidV3Builder  # noqa: E402
from tasks.sprint_blocks import TENDON_SCALE, SprintBlocksTask  # noqa: E402


class SprintBlocksP95Task(SprintBlocksTask):
    name = "sprint_blocks_p95"
    body_note = "v3 anatomy, p95 profile (strength x1.32, speed x1.2, tendon x1.5, activation x0.87), planar root, 1 ms physics"

    def builder(self):
        if self.body == "v2":
            return HumanoidV2Builder(self.mode, strength=self.strength, wrists=self.wrists, profile="p95")
        return HumanoidV3Builder(self.mode, strength=self.strength, wrists=self.wrists, stiffness_scale=TENDON_SCALE,
                                 profile="p95")

    def title(self):
        return "robolab: sprint from blocks (v3 body, p95 profile), Bolt keyframes"


TASK = SprintBlocksP95Task
