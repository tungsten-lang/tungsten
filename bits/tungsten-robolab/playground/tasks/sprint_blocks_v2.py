"""Sprint from starting blocks (tasks/sprint_blocks.py: same blocks, rules,
metrics and Bolt reference) on the rigid-tendon v2 anatomy at its own 2 ms
timestep (control every 4 ms), the body challenger to the v3 default."""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # run as a script too
from tasks.sprint_blocks import SprintBlocksTask  # noqa: E402


class SprintBlocksV2Task(SprintBlocksTask):
    name = "sprint_blocks_v2"
    body = "v2"
    timestep = 0.002
    body_note = "v2 anatomy (rigid tendons), planar root, strength 1.0, 2 ms physics"


TASK = SprintBlocksV2Task
