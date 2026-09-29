"""long_jump_p95e (the 7.02 m/s runner) with the check mark 0.06 m longer
(37.55 m) after a 3.5 mm foul: a params file for this task sets
j_board_shift 1.05 and ik_gap0 + 0.06, so the run-up, its planning and the
program's board feedback are those of long_jump_p95e.
ROBOLAB_LJ_APPROACH overrides it."""

import os

from tasks.long_jump_p95 import LongJumpP95Task


class LongJumpP95FTask(LongJumpP95Task):
    name = "long_jump_p95f"
    board_x = float(os.environ.get("ROBOLAB_LJ_APPROACH", "37.55"))


TASK = LongJumpP95FTask
