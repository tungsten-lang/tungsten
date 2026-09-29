"""long_jump_p95 (95th-percentile muscles and tendons, average 1.75 m / 67.5 kg
skeleton) on the v4 anatomy: the v3 body with its muscle, segment and contact
parameters from the literature calibration playground/calibrations/v4.json
(HumanoidV4Builder in body.py; ROBOLAB_CALIB names another). Same scene,
rules, metrics and seeded starts as long_jump_p95 (World Athletics TR 29-30).
The runner is the sprint_top_speed_v4_p95 champion (RunRISkill). The check
mark is a placeholder (the v3 p95's 37.8 m) until the run-up is measured on
this body; ROBOLAB_LJ_APPROACH overrides it."""

import os

from body import HumanoidV4Builder
from tasks.long_jump_p95 import LongJumpP95Task
from tasks.long_jump_v3 import TENDON_SCALE


class LongJumpV4P95Task(LongJumpP95Task):
    name = "long_jump_v4_p95"

    def builder(self):
        kw = dict(strength=self.strength, wrists=self.wrists)
        if self.profile:
            kw.update(profile=self.profile, profile_parts=self.profile_parts)
        return HumanoidV4Builder(self.mode, stiffness_scale=TENDON_SCALE, calib=os.environ.get("ROBOLAB_CALIB") or "v4", **kw)

    def title(self):
        return "robolab: long jump with a sprint run-up (v4 anatomy, 95th-percentile muscles and tendons)"


TASK = LongJumpV4P95Task
