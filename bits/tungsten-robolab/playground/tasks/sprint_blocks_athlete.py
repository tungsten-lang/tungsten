"""Sprint from starting blocks (tasks/sprint_blocks.py: same blocks, rules,
metrics and Bolt reference) on an ATHLETE v3 body: every muscle's peak force
x1.5 (sprinters' leg strength relative to body mass is well above the
average adult's the default body models; the batting skill's `athlete` body
uses the same factor). A declared body challenger, not the default."""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # run as a script too
from tasks.sprint_blocks import SprintBlocksTask  # noqa: E402


class SprintBlocksAthleteTask(SprintBlocksTask):
    name = "sprint_blocks_athlete"
    strength = float(os.environ.get("SPRINT_STRENGTH", "1.5"))
    body_note = "v3 anatomy, strength x1.5 (athlete), planar root, 1 ms physics"

    def title(self):
        return "robolab: sprint from blocks (v3 athlete body, strength x1.5), Bolt keyframes"


TASK = SprintBlocksAthleteTask
