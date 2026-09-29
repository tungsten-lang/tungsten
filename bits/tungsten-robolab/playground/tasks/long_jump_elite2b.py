"""long_jump_elite2 (the 6.56 m/s elite2 runner, literature-based body) with the
check mark 0.04 m longer (38.89 m): on 80 fresh starts (seeds 9001-9064 and the
arena's 601-616) the take-off foot's front is over the line on 6 (7.5 %) and
short of the line by 0.2-0.5 m on the others; a params file for this task sets
j_board_shift 1.11 and ik_gap0 + 0.04, so the run-up, its planning and the
program's board feedback are exactly those of long_jump_elite2 and only the line
moves. 0.08 and 0.12 m were worse (the fouls that remain are large overshoots
of a run-up that cannot be steered on this body, not margins). Same body,
scene, rules and metrics. ROBOLAB_LJ_APPROACH overrides it."""

import os

from tasks.long_jump_elite2 import LongJumpElite2Task


class LongJumpElite2BTask(LongJumpElite2Task):
    name = "long_jump_elite2b"
    board_x = float(os.environ.get("ROBOLAB_LJ_APPROACH", "38.89"))


TASK = LongJumpElite2BTask
