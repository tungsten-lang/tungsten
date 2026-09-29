"""long_jump_p95 with the check mark of the faster p95 runner (the
sprint_top_speed_p95 champion of 2026-09-28 00:19, params/run_ri_p95_sp2.txt,
6.94 m/s peak): 38.6 m from the start to the foul line (long_jump_p95: 37.8 m,
for the 6.66 m/s runner). Same body, scene, rules and metrics.
ROBOLAB_LJ_APPROACH overrides it as for every long-jump task."""

import os

from tasks.long_jump_p95 import LongJumpP95Task


class LongJumpP95BTask(LongJumpP95Task):
    name = "long_jump_p95b"
    board_x = float(os.environ.get("ROBOLAB_LJ_APPROACH", "38.6"))


TASK = LongJumpP95BTask
