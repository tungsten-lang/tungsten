"""long_jump_elite with the check mark of the ideal take-off program (`j_ik`,
playground/long_jump_limits.py): the ideal plant step (2.0 m) is shorter than
the gait's, so the check mark moves 1.17 m: 42.83 m from the start to the foul
line (long_jump_elite: 44.0 m). A params file for this task sets
j_board_shift 1.17 so the run-up and its planning are unchanged. The ELITE
profile is provisional (profiles/elite.json magnitudes unverified).
ROBOLAB_LJ_APPROACH overrides it."""

import os

from tasks.long_jump_elite import LongJumpEliteTask


class LongJumpEliteCTask(LongJumpEliteTask):
    name = "long_jump_elite_c"
    board_x = float(os.environ.get("ROBOLAB_LJ_APPROACH", "42.83"))


TASK = LongJumpEliteCTask
