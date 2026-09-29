"""long_jump_p95c with the check mark 0.08 m longer (37.53 m): the ideal
take-off program's take-off foot front lands 0.08 +- 0.06 m behind the line on
held-out starts, and 2 of 16 broke it by 1-14 mm; a params file for this task
sets j_board_shift 1.07 and ik_gap0 + 0.08, so the run-up, its planning and
the program's board feedback are exactly those of long_jump_p95c.
ROBOLAB_LJ_APPROACH overrides it."""

import os

from tasks.long_jump_p95 import LongJumpP95Task


class LongJumpP95DTask(LongJumpP95Task):
    name = "long_jump_p95d"
    board_x = float(os.environ.get("ROBOLAB_LJ_APPROACH", "37.53"))


TASK = LongJumpP95DTask
