"""long_jump_p95b with the check mark of the ideal take-off program (`j_ik`,
playground/long_jump_limits.py): the ideal plant step is short, so the take-off
foot lands ~1.15 m further back than the gait's plant; the check mark moves
with it: 37.45 m from the start to the foul line (long_jump_p95b: 38.6 m).
A params file for this task moves the planner's aim point j_aim by the same
1.15 m, so the run-up is unchanged. ROBOLAB_LJ_APPROACH overrides it."""

import os

from tasks.long_jump_p95 import LongJumpP95Task


class LongJumpP95CTask(LongJumpP95Task):
    name = "long_jump_p95c"
    board_x = float(os.environ.get("ROBOLAB_LJ_APPROACH", "37.45"))


TASK = LongJumpP95CTask
