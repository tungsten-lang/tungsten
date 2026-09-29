"""Run on the v3 anatomy: the v2 body (biarticulars, toes, calibrated speeds,
strength 1.0) with series-elastic Achilles and quadriceps tendons
(HumanoidV3Builder in body.py: every muscle, peak, speed and length range as
v2; the plantarflexors' and knee extensors' fibres act through linear
tension-only tendons, Achilles 200 N/mm at 5 cm, quadriceps 250 N/mm at 4.5 cm).

Same RunSkill (bin/robolab_run_v3 is a copy of bin/robolab_run_v2, the build
that recorded params/run_v2.txt), scene, metrics and score as run_v2.
Physics runs at a 1 ms timestep (the fibre-tendon mode is ~450-500 rad/s);
the controller still ticks every 4 ms. Reset leaves every tendon at its slack
length for the starting posture (settle_fibers).

ROBOLAB_V3_TIMESTEP overrides the timestep; ROBOLAB_V3_TENDON_SCALE scales
every tendon stiffness (sensitivity checks; 1.0 is the model);
ROBOLAB_V3_RIGID=1 builds the rigid v2 body instead, at the v3 timestep (the
control for the timestep change).
"""

import os

from body import HumanoidV2Builder, HumanoidV3Builder, settle_fibers
from bridge import ROOT
from tasks.run_v2 import RunV2Task

TIMESTEP = float(os.environ.get("ROBOLAB_V3_TIMESTEP", "0.001"))
TENDON_SCALE = float(os.environ.get("ROBOLAB_V3_TENDON_SCALE", "1.0"))
RIGID = os.environ.get("ROBOLAB_V3_RIGID", "") not in ("", "0")


class RunV3Task(RunV2Task):
    name = "run_v3"
    controller = os.path.join(ROOT, "bin", "robolab_run_v3")
    timestep = TIMESTEP

    def builder(self):
        if RIGID:
            return HumanoidV2Builder(self.mode, strength=self.strength, wrists=self.wrists)
        return HumanoidV3Builder(self.mode, strength=self.strength, wrists=self.wrists,
                                 stiffness_scale=TENDON_SCALE)

    def reset(self, m, d):
        super().reset(m, d)
        settle_fibers(m, d)

    def title(self):
        return "robolab: run, v3 anatomy (v2 + elastic Achilles and quadriceps tendons)"


TASK = RunV3Task
