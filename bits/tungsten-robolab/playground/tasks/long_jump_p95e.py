"""long_jump_p95 for the 7.02 m/s p95 runner (the sprint_top_speed_p95
champion of 2026-09-28 03:53) with the ideal take-off program: check mark
37.49 m (a params file sets j_board_shift 1.11 so the run-up plans against the
38.6 m board of long_jump_p95b and the program's plant step lands on this
board). Same body, scene, rules and metrics. ROBOLAB_LJ_APPROACH overrides it."""

import os

from tasks.long_jump_p95 import LongJumpP95Task


class LongJumpP95ETask(LongJumpP95Task):
    name = "long_jump_p95e"
    board_x = float(os.environ.get("ROBOLAB_LJ_APPROACH", "37.49"))


TASK = LongJumpP95ETask
