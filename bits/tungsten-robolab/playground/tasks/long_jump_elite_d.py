"""long_jump_elite_c with the check mark 0.08 m longer (42.91 m), as
long_jump_p95d: a params file for this task sets j_board_shift 1.09 and
ik_gap0 + 0.08, so the run-up, its planning and the program's board feedback
are those of long_jump_elite_c. ELITE profile: provisional (magnitudes
unverified). ROBOLAB_LJ_APPROACH overrides it."""

import os

from tasks.long_jump_elite import LongJumpEliteTask


class LongJumpEliteDTask(LongJumpEliteTask):
    name = "long_jump_elite_d"
    board_x = float(os.environ.get("ROBOLAB_LJ_APPROACH", "42.91"))


TASK = LongJumpEliteDTask
