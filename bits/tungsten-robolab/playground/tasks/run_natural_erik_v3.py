"""Natural running against Erik's keyframes (tasks/run_natural_erik.py: the
reference, practice terms and 3-4 m/s band) on the v3 anatomy: elastic
Achilles and quadriceps tendons, 1 ms physics (tasks/run_natural_v3.py). A
challenger task for run_natural_erik* trials (arena.py eval ... --task
run_natural_erik_v3): sprint-style keyframe sets lean on tendon recoil."""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # run as a script too
from tasks.run_natural_erik import RunNaturalErikTask  # noqa: E402
from tasks.run_natural_v3 import V3Body  # noqa: E402


class RunNaturalErikV3Task(V3Body, RunNaturalErikTask):
    name = "run_natural_erik_v3"

    def title(self):
        return "robolab: natural run against Erik's keyframes (v3 anatomy: elastic tendons)"


TASK = RunNaturalErikV3Task


if __name__ == "__main__":
    import tasks.run_natural as rn
    rn.RunNaturalTask = RunNaturalErikV3Task
    rn.main()
