"""long_jump_run on the LITERATURE-BASED elite-sprinter body (body_profile.py,
profiles/elite2.json, checked against the papers on 2026-09-28; supersedes
profiles/elite.json): its muscle parts (strength, speed, tendon, activation)
on the average 1.75 m / 67.5 kg skeleton, as the sprint_top_speed_elite2
trial. Runner: the sprint_top_speed_elite2 champion (RunRISkill). Same scene,
rules, metrics and seeded starts as long_jump_run; the check mark is this
athlete's own: 38.85 m, for a run-up planned against a 40.0 m board (a params file sets j_board_shift 1.15) with the ideal take-off program (ROBOLAB_LJ_APPROACH overrides it)."""

import os

from tasks.long_jump_run import LongJumpRunTask


class LongJumpElite2Task(LongJumpRunTask):
    name = "long_jump_elite2"
    profile = "elite2"
    profile_parts = "strength,speed,tendon,activation"
    board_x = float(os.environ.get("ROBOLAB_LJ_APPROACH", "38.85"))
    run_speed = 5.2

    def title(self):
        return "robolab: long jump with a sprint run-up (v3 anatomy, literature-based elite-sprinter muscles)"


TASK = LongJumpElite2Task
