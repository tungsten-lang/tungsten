"""Natural running (tasks/run_natural.py: same reference, metrics, score and
3-4 m/s band) on the v3 anatomy: the v2 body with series-elastic Achilles and
quadriceps tendons (HumanoidV3Builder in body.py), 1 ms physics, control every
4 ms. Reset (standing or flying start) leaves every tendon at its slack length
(settle_fibers). The skill binary is run_natural's; the contraction the
reflexes see is the fibre's (spindle), the posture geometry the whole MTU's.

ROBOLAB_V3_TIMESTEP / ROBOLAB_V3_TENDON_SCALE as in tasks/run_v3.py.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # run as a script too
from body import HumanoidV3Builder, settle_fibers  # noqa: E402
from bridge import ROOT  # noqa: E402
from tasks.run_natural import RunNaturalTask  # noqa: E402

TIMESTEP = float(os.environ.get("ROBOLAB_V3_TIMESTEP", "0.001"))
TENDON_SCALE = float(os.environ.get("ROBOLAB_V3_TENDON_SCALE", "1.0"))


class V3Body:
    """Mixin: the v3 (elastic-tendon) body at the v3 timestep."""
    timestep = TIMESTEP
    body_note = "v3 anatomy (v2 + series-elastic Achilles and quadriceps tendons), planar root, strength 1.0, 1 ms physics"

    def builder(self):
        return HumanoidV3Builder(self.mode, strength=self.strength, wrists=self.wrists, stiffness_scale=TENDON_SCALE)

    def reset(self, m, d):
        super().reset(m, d)
        settle_fibers(m, d)


class RunNaturalV3Task(V3Body, RunNaturalTask):
    name = "run_natural_v3"
    controller = os.path.join(ROOT, "bin", "robolab_run_natural")

    def title(self):
        return "robolab: natural run (human keyframes, v3 anatomy: elastic Achilles + patellar tendons)"


TASK = RunNaturalV3Task


if __name__ == "__main__":
    import tasks.run_natural as rn
    rn.RunNaturalTask = RunNaturalV3Task
    rn.main()
