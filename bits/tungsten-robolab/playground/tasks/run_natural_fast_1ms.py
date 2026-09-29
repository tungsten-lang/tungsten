"""Fast natural running (tasks/run_natural_fast.py: reference at the measured
speed, 4.5-6 m/s band, fast-run practice score) on the rigid v2 body at a
1 ms physics timestep: the control for the v3 body's timestep (the v2 sprint
ran 4.04 m/s at 2 ms and 4.58 at 1 ms with the same practice, README "v3
anatomy"). Control still ticks every 4 ms."""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # run as a script too
from tasks.run_natural_fast import RunNaturalFastTask  # noqa: E402


class RunNaturalFast1msTask(RunNaturalFastTask):
    name = "run_natural_fast_1ms"
    timestep = 0.001
    body_note = "v2 anatomy (rigid tendons), planar root, strength 1.0, 1 ms physics"

    def title(self):
        return "robolab: fast natural run (human keyframes at speed, v2 anatomy, 1 ms physics)"


TASK = RunNaturalFast1msTask


if __name__ == "__main__":
    import tasks.run_natural as rn
    rn.RunNaturalTask = RunNaturalFast1msTask
    rn.main()
