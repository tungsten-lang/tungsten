"""Practice task (tasks/sprint_touch.py's metrics, starts and objectives) on the
v4 anatomy (tasks/run_v4.py: calibration playground/calibrations/v4.json
unless ROBOLAB_CALIB names another)."""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # run as a script too
from body import HumanoidV4Builder, settle_fibers  # noqa: E402
from tasks.run_natural_v3 import TIMESTEP  # noqa: E402
from tasks.sprint_touch import SprintTouchTask  # noqa: E402


class SprintTouchV4Task(SprintTouchTask):
    name = "sprint_touch_v4"
    timestep = TIMESTEP
    # the flying start's snapshot set (fly_touch 2): playground/cache/sprint_touch_<snap>[_acc][_s<ver>].npz;
    # ROBOLAB_SNAP names another body's (e.g. run_v3_p95: the v3 P95 champion at 6.9 m/s, fibre states included)
    snap = os.environ.get("ROBOLAB_SNAP", "run_v4")
    body_note = "v4 anatomy (calibrated), planar root, 1 ms physics"

    def builder(self):
        return HumanoidV4Builder(self.mode, strength=self.strength, wrists=self.wrists,
                                 calib=os.environ.get("ROBOLAB_CALIB") or "v4")

    def reset(self, m, d):
        super().reset(m, d)
        if not (self.start == "flying" and self.fly_touch >= 1.5):
            settle_fibers(m, d)

    def title(self):
        return "robolab: sprint practice, v4 anatomy (calibrated)"


TASK = SprintTouchV4Task
