"""long_jump_elite2 (the literature-based elite-sprinter muscles of
profiles/elite2.json on the average skeleton) on the v4 anatomy (the v3 body with
its muscle, segment and contact parameters from the literature calibration
playground/calibrations/v4.json, HumanoidV4Builder in body.py). Same scene,
rules, metrics and seeded starts as long_jump_elite2. The runner is the
sprint_top_speed_v4_elite2 champion (RunRISkill). The check mark is a
placeholder (the v3 elite2's 38.85 m) until the run-up is measured on this
body; ROBOLAB_LJ_APPROACH overrides it."""

import os

from body import HumanoidV4Builder
from tasks.long_jump_elite2 import LongJumpElite2Task
from tasks.long_jump_v3 import TENDON_SCALE


class LongJumpV4Elite2Task(LongJumpElite2Task):
    name = "long_jump_v4_elite2"

    def builder(self):
        kw = dict(strength=self.strength, wrists=self.wrists)
        if self.profile:
            kw.update(profile=self.profile, profile_parts=self.profile_parts)
        return HumanoidV4Builder(self.mode, stiffness_scale=TENDON_SCALE, calib=os.environ.get("ROBOLAB_CALIB") or "v4", **kw)

    def title(self):
        return "robolab: long jump with a sprint run-up (v4 anatomy, literature-based elite-sprinter muscles)"


TASK = LongJumpV4Elite2Task
