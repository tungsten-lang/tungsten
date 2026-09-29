"""long_jump_p95e (the 7.02 m/s p95 runner) with the check mark 0.05 m longer
(37.54 m): the penultimate-touchdown take-off program (`j_ik` with `ik_from 1`,
playground/long_jump_limits.py) puts the take-off foot's front 0.06 +- 0.05 m
behind the line on 112 fresh starts and 3 of them over it by 5-49 mm; a params
file for this task sets j_board_shift 1.06 and ik_gap0 + 0.05, so the run-up,
its planning and the program's board feedback are exactly those of
long_jump_p95e. Same body, scene, rules and metrics.
ROBOLAB_LJ_APPROACH overrides it."""

import os

from tasks.long_jump_p95 import LongJumpP95Task


class LongJumpP95GTask(LongJumpP95Task):
    name = "long_jump_p95g"
    board_x = float(os.environ.get("ROBOLAB_LJ_APPROACH", "37.54"))


TASK = LongJumpP95GTask
