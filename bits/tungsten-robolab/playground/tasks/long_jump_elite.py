"""long_jump_run on the ELITE-SPRINTER body (body_profile.py,
profiles/elite.json: a separate, labelled body, not a population percentile;
per-muscle strength per kg x1.25-1.6 (hip extensors, hamstrings and hip
flexors most), muscle speed x1.3, tendon stiffness x1.3, activation time
constants x0.8; the average 1.75 m / 67.5 kg skeleton; the profile marks its
magnitudes unverified), with the sprint_top_speed_elite champion's runner
(RunRISkill, params/run_ri_elite.txt, 7.44 m/s peak). Same scene, rules,
metrics and seeded starts as long_jump_run; the check mark is this athlete's
own (default 44.0 m, within a 45 m runway: the elite runner is still accelerating at 40 m; ROBOLAB_LJ_APPROACH overrides it)."""

import os

from tasks.long_jump_run import LongJumpRunTask


class LongJumpEliteTask(LongJumpRunTask):
    name = "long_jump_elite"
    profile = "elite"
    profile_parts = "strength,speed,tendon,activation"
    board_x = float(os.environ.get("ROBOLAB_LJ_APPROACH", "44.0"))
    run_speed = 5.6

    def title(self):
        return "robolab: long jump with a sprint run-up (v3 anatomy, elite-sprinter muscles and tendons)"


TASK = LongJumpEliteTask
