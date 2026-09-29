"""Natural running scored against MOTION CAPTURE: run_natural (v2 body,
standing start, 3-4 m/s band, same seeds and guards in the arena) with the
reference's hip, knee and ankle curves the mean of Fukuchi et al. 2017's
treadmill runners (tasks/run_natural.py MocapReference; 2.5 / 3.5 / 4.5 m/s,
interpolated to the MEASURED speed of the scored tail). Trunk, arms and toes
stay the literature curves (the dataset has none).

The practice score adds PracticeExtras (tasks/run_natural_erik.py): a 3.2 m/s
speed margin, peak-GRF (> 4 BW) and loading-rate (> 100 BW/s) penalties and
the defining poses (TD reach and foot, MS knee yield, KL knee drive) against
the mocap keyframes.

The skill aims at the mocap poses when its params carry the mocap keyframe
set (params/keyframes_mocap35.txt: ref_<td|ms|hr|kl|to>_* at 3.5 m/s, the same
values as the Keyframe Bench set "Mocap: Fukuchi 2017, 3.5 m/s",
playground/refs/fukuchi2017/editor/*.json).
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # run as a script too
import numpy as np  # noqa: E402

from bridge import ROOT  # noqa: E402
from tasks.run_natural import MocapReference, RunNaturalTask, naturalness  # noqa: E402
from tasks.run_natural_erik import PracticeExtras  # noqa: E402
from tasks.run_natural_fast import tail_speed  # noqa: E402


class RunNaturalMocapTask(PracticeExtras, RunNaturalTask):
    name = "run_natural_mocap"
    controller = os.path.join(ROOT, "bin", "robolab_run_natural")

    def reference(self):
        return MocapReference(self.ref_speed)

    def metrics(self, m, d, log):
        out = super().metrics(m, d, log)
        v = float(np.clip(tail_speed(self.jrec, self.tail_s), 2.5, 4.5))
        out.update(naturalness(self.jrec, MocapReference(v), self.tail_s))
        out["ref_speed_scored"] = round(v, 3)
        lo, hi = self.speed_band
        out["in_band"] = bool(lo <= out.get("speed", 0.0) <= hi)
        return out

    def title(self):
        return "robolab: natural run against motion capture (Fukuchi 2017 mean curves, v2 anatomy)"


TASK = RunNaturalMocapTask


if __name__ == "__main__":
    import tasks.run_natural as rn
    rn.RunNaturalTask = RunNaturalMocapTask
    rn.main()
