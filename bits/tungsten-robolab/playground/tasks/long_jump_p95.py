"""long_jump_run on the 95th-percentile body (body_profile.py,
profiles/p95.json): the v3 anatomy with P95 muscle strength per kg (x1.32),
muscle shortening speed (x1.2), tendon stiffness (x1.5) and activation time
constants (x0.87), on the average skeleton (1.75 m, 67.5 kg), as run_v3_p95 /
sprint_blocks_p95. Same scene, rules, metrics and seeded starts as
long_jump_run; the check mark is this athlete's own (default 37.8 m;
ROBOLAB_LJ_APPROACH overrides it)."""

import os

from tasks.long_jump_run import LongJumpRunTask

CHECK_MARK_P95 = float(os.environ.get("ROBOLAB_LJ_APPROACH", "37.8"))


class LongJumpP95Task(LongJumpRunTask):
    name = "long_jump_p95"
    profile = "p95"
    profile_parts = "strength,speed,tendon,activation"
    board_x = CHECK_MARK_P95
    run_speed = 5.2

    def title(self):
        return "robolab: long jump with a sprint run-up (v3 anatomy, 95th-percentile muscles and tendons)"


TASK = LongJumpP95Task
