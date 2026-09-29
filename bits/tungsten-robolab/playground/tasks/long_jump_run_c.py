"""long_jump_run (average v3 body) with the check mark of the ideal take-off
program (`j_ik`, playground/long_jump_limits.py): the ideal plant step (1.49 m)
is shorter than the gait's, so the check mark moves 0.57 m: 34.70 m from the
start to the foul line (long_jump_run_b: 35.27 m). A params file for this task
sets j_board_shift 0.567 so the run-up and its planning are unchanged.
ROBOLAB_LJ_APPROACH overrides it."""

import os

from tasks.long_jump_run import LongJumpRunTask


class LongJumpRunCTask(LongJumpRunTask):
    name = "long_jump_run_c"
    board_x = float(os.environ.get("ROBOLAB_LJ_APPROACH", "34.70"))


TASK = LongJumpRunCTask
