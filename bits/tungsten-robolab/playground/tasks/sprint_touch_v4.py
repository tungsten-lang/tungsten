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

    # practice only (default 1.0 = the arena's start): a perturbed standing start (seed) scaled by this factor,
    # so a search can train on starts harder than the arena's (--attrs start_noise=1.5)
    start_noise = 1.0

    def reset(self, m, d):
        super().reset(m, d)
        if not (self.start == "flying" and self.fly_touch >= 1.5):
            if self.start_noise != 1.0 and self.seed is not None and self.start != "flying":
                self._extra_start_noise(m, d)
            settle_fibers(m, d)

    def _extra_start_noise(self, m, d):
        """RunTask.reset's perturbation (seed: N(0, 0.04) rad on seven joints in order, N(0, 0.02) on the pelvis
        pitch) taken (start_noise - 1) more times."""
        import numpy as np
        rng = np.random.default_rng(self.seed)
        k = self.start_noise - 1.0
        for j in ("l_hip_flex", "r_hip_flex", "l_knee", "r_knee", "l_ankle", "r_ankle", "spine_flex"):
            a = m.joint(j).qposadr[0]
            lo, hi = m.jnt_range[m.joint(j).id]
            d.qpos[a] = float(np.clip(d.qpos[a] + k * rng.normal(0.0, 0.04), lo, hi))
        d.qpos[m.joint("root_pitch").qposadr[0]] += k * rng.normal(0.0, 0.02)

    def title(self):
        return "robolab: sprint practice, v4 anatomy (calibrated)"


TASK = SprintTouchV4Task
