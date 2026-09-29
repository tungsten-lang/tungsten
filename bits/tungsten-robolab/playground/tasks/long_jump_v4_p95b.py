"""long_jump_v4_p95 (the sprint_top_speed_v4_p95 champion's runner on the v4
anatomy, 95th-percentile muscles and tendons) with the check mark 44.0 m, the
longest a standard runway allows (World Athletics TR 29.1: 40 m, 45 m where
possible): the crouched high-cadence runner reaches 6.4 m/s at 37.5 m, 6.7 at
45 m and 6.8 at 55 m, so the run-up is as long as the rules permit.
ROBOLAB_LJ_APPROACH overrides it."""

import os

from tasks.long_jump_v4_p95 import LongJumpV4P95Task


class LongJumpV4P95BTask(LongJumpV4P95Task):
    name = "long_jump_v4_p95b"
    board_x = float(os.environ.get("ROBOLAB_LJ_APPROACH", "44.0"))


TASK = LongJumpV4P95BTask
