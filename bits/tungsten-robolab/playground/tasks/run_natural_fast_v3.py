"""Fast natural running (tasks/run_natural_fast.py: the reference at the
measured speed, 4.5-6 m/s band, fast-run practice score) on the v3 anatomy
(elastic Achilles and quadriceps tendons, 1 ms physics; see
tasks/run_natural_v3.py)."""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # run as a script too
from tasks.run_natural_fast import RunNaturalFastTask  # noqa: E402
from tasks.run_natural_v3 import V3Body  # noqa: E402


class RunNaturalFastV3Task(V3Body, RunNaturalFastTask):
    name = "run_natural_fast_v3"

    def title(self):
        return "robolab: fast natural run (human keyframes at speed, v3 anatomy: elastic tendons)"


TASK = RunNaturalFastV3Task


if __name__ == "__main__":
    import tasks.run_natural as rn
    rn.RunNaturalTask = RunNaturalFastV3Task
    rn.main()
