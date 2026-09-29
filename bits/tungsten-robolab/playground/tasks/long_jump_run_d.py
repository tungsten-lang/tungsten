"""long_jump_run_c (average v3 body, ideal take-off program) with the check
mark 0.07 m longer (34.77 m) after 3-4.5 cm fouls: a params file for this
task sets j_board_shift 0.497 and ik_gap0 + 0.07, so the run-up, its planning
and the program's board feedback are those of long_jump_run_c.
ROBOLAB_LJ_APPROACH overrides it."""

import os

from tasks.long_jump_run import LongJumpRunTask


class LongJumpRunDTask(LongJumpRunTask):
    name = "long_jump_run_d"
    board_x = float(os.environ.get("ROBOLAB_LJ_APPROACH", "34.77"))


TASK = LongJumpRunDTask
