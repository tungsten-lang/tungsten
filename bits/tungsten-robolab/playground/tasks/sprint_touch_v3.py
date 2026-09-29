"""Touch-only sprint (tasks/sprint_touch.py) on the v3 anatomy: elastic
Achilles and quadriceps tendons, 1 ms physics (tasks/run_natural_v3.py)."""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # run as a script too
from tasks.run_natural_v3 import V3Body  # noqa: E402
from tasks.sprint_touch import SprintTouchTask  # noqa: E402


class SprintTouchV3Task(V3Body, SprintTouchTask):
    name = "sprint_touch_v3"
    # the flying start's snapshots come from the champion on the same body
    # (ROBOLAB_PROFILE=p95: the P95 champion's)
    snap = "run_v3_p95" if os.environ.get("ROBOLAB_PROFILE", "") == "p95" else "run_v3"

    def reset(self, m, d):
        if self.start == "flying" and self.fly_touch >= 1.5:
            # the snapshot carries its own fibre (tendon) states
            SprintTouchTask.reset(self, m, d)
        else:
            super().reset(m, d)

    def title(self):
        return "robolab: touch-only sprint (one touchdown keyframe + phase bursts, v3 anatomy: elastic tendons)"


TASK = SprintTouchV3Task


if __name__ == "__main__":
    import tasks.run_natural as rn
    rn.RunNaturalTask = SprintTouchV3Task
    rn.main()
