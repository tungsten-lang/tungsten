"""Run on the v2 anatomy: biarticular muscles (rectus femoris, hamstrings,
gastrocnemius) and toe joints, strength 1.0. Same skill and metrics as run."""

from body import HumanoidV2Builder
from tasks.run import RunTask


class RunV2Task(RunTask):
    name = "run_v2"
    controller = None
    # sprint objective: sustained speed keeps paying up to 10 m/s
    speed_cap = 10.0

    def builder(self):
        return HumanoidV2Builder(self.mode, strength=self.strength, wrists=self.wrists)

    def title(self):
        return "robolab: run, v2 anatomy (biarticulars + toes)"


TASK = RunV2Task
