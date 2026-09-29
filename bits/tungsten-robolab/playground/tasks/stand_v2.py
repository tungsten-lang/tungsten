"""Stand bring-up on the v2 anatomy (calibrated speeds, biarticulars, toes)."""

from body import HumanoidV2Builder
from tasks.stand import StandTask


class StandV2Task(StandTask):
    name = "stand_v2"
    controller = None

    def builder(self):
        return HumanoidV2Builder(self.mode, strength=self.strength, wrists=self.wrists)


TASK = StandV2Task
