"""Practice-only variant of run_natural (same body, start, reference and
metrics, so the arena scores it exactly as run_natural) whose score weights
the look errors left after round 1:

  touchdown   the stance knee at touchdown (human ~18 deg; round 1 lands at
              ~36, heel first with the ankle ~22 deg dorsiflexed): -0.3 per
              degree of knee error and -0.15 per degree of ankle error at TD
  heel tuck   the swing knee at the other leg's mid-stance (human ~110 deg;
              round 1 ~80): -0.2 per degree short
  arms        shoulder swing peak-to-peak (human ~80 deg at 3.5 m/s; round 1
              ~99): -0.1 per degree beyond +-5 deg
  impact      peak vertical GRF above 3 body weights (human 2.5-3; round 1
              ~4): -3 per body weight (run_natural charges above 4)
  legs        the knee and ankle cycle errors count 0.5 more
  speed       the practice band starts at 3.2 m/s, a margin above the arena
              guard's 3.0 (look1, practised on 3-4 m/s, settled at 2.95-3.05
              m/s and failed the guard on 7 of 12 held-out starts)

    .venv/bin/python playground/search.py run_natural_look --init params/run_natural.txt ...
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # run as a script too
import numpy as np  # noqa: E402

from bridge import ROOT  # noqa: E402
from tasks.run_natural import RunNaturalTask  # noqa: E402


def event_mean(metrics, event, role, default=None):
    """Mean achieved angle (deg) of `role` (e.g. st_knee) at `event` (TD / MS /
    TO) over both steps, and its reference."""
    rows = [metrics.get("keyframes", {}).get(s + "_" + event, {}).get(role) for s in ("R", "L")]
    rows = [r for r in rows if r]
    if not rows:
        return default, default
    return float(np.mean([r[1] for r in rows])), float(np.mean([r[0] for r in rows]))


def look_penalty(metrics, human_arm=80.0):
    """The extra look terms (>= 0; see the module docstring)."""
    if "keyframes" not in metrics:
        return 60.0
    p = 0.5 * (metrics.get("kin_knee", 60.0) + metrics.get("kin_ankle", 60.0))
    k, kr = event_mean(metrics, "TD", "st_knee", 60.0)
    a, ar = event_mean(metrics, "TD", "st_ankle", 60.0)
    p += 0.3 * abs(k - kr) + 0.15 * abs(a - ar)
    t, tr = event_mean(metrics, "MS", "sw_knee", 0.0)
    p += 0.2 * max(0.0, tr - t)
    p += 0.1 * max(0.0, abs(metrics.get("arm_swing", 0.0) - human_arm) - 5.0)
    p += 3.0 * max(0.0, metrics.get("peak_grf", 0.0) - 3.0)
    return p


class RunNaturalLookTask(RunNaturalTask):
    name = "run_natural_look"
    controller = os.path.join(ROOT, "bin", "robolab_run_natural")
    speed_band = (3.2, 4.0)  # practice only: the arena scores run_natural's 3-4 m/s

    def score(self, metrics):
        s = super().score(metrics)
        if s <= -1e5:
            return s
        # run_natural already charges 3 per body weight above 4
        s += 3.0 * max(0.0, metrics.get("peak_grf", 0.0) - 4.0)
        return s - look_penalty(metrics, 2.0 * self.reference().arm)


TASK = RunNaturalLookTask
