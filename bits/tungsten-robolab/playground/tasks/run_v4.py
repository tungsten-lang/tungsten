"""Run on the v4 anatomy: the v3 body (series-elastic Achilles and quadriceps)
with its muscle, segment and contact parameters from a literature
calibration (HumanoidV4Builder in body.py; calibration
playground/calibrations/v4.json unless ROBOLAB_CALIB names another). Same
RunSkill, scene, metrics, score, 1 ms physics and reset as run_v3; profiles
(ROBOLAB_PROFILE=p95 / elite2) apply on top as for every builder."""

import os

from body import HumanoidV4Builder
from bridge import ROOT
from tasks.run_v3 import TENDON_SCALE, RunV3Task


class RunV4Task(RunV3Task):
    name = "run_v4"
    controller = os.path.join(ROOT, "bin", "robolab_run_ri")

    def builder(self):
        return HumanoidV4Builder(self.mode, strength=self.strength, wrists=self.wrists, stiffness_scale=TENDON_SCALE,
                                 calib=os.environ.get("ROBOLAB_CALIB") or "v4")

    def title(self):
        return "robolab: run, v4 anatomy (calibrated muscles, segments and contact)"


TASK = RunV4Task
