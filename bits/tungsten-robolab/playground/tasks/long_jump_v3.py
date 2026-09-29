"""Long jump on the v3 anatomy: the v2 body (calibrated speeds, biarticulars,
toes, strength 1.0) with series-elastic Achilles and quadriceps tendons
(HumanoidV3Builder in body.py). Same LongJumpSkill (bin/robolab_long_jump_v3
is a copy of bin/robolab_long_jump_v2, the build that recorded
params/long_jump_v2.txt), scene, sensors, metrics and scoring as long_jump_v2.

Physics at a 1 ms timestep (control every 4 ms); reset leaves every tendon at
its slack length for the starting posture. The run-up is the v3 athlete's own
check mark, 12.74 m (long_jump_v2: 12.9 m). Environment overrides as for
long_jump_v2 (ROBOLAB_LJ_APPROACH, ROBOLAB_LJ_SEED, ...; task.seed, set by
search.py --seeds and arena.py, perturbs the start as in long_jump_v2s), plus
ROBOLAB_V3_TIMESTEP, ROBOLAB_V3_TENDON_SCALE and ROBOLAB_V3_RIGID=1 (the rigid
v2 body at the v3 timestep) as in run_v3.
"""

import os

from body import HumanoidV2Builder, HumanoidV3Builder, settle_fibers
from tasks.long_jump import ROOT_BIN
from tasks.long_jump_v2 import LongJumpV2Task
from tasks.long_jump_v2s import SeededStart

TIMESTEP = float(os.environ.get("ROBOLAB_V3_TIMESTEP", "0.001"))
TENDON_SCALE = float(os.environ.get("ROBOLAB_V3_TENDON_SCALE", "1.0"))
RIGID = os.environ.get("ROBOLAB_V3_RIGID", "") not in ("", "0")
# The v3 athlete's check mark (start to foul line): its practised run-up puts the
# take-off foot closest to the board from 12.74 m (a scan of 12.2-13.6 m in 2 cm
# steps with the stage-E params; 12.9 m, the v2 athlete's mark, leaves it 0.44 m
# behind). ROBOLAB_LJ_APPROACH overrides it, as for every long-jump task.
CHECK_MARK_V3 = float(os.environ.get("ROBOLAB_LJ_APPROACH", "12.74"))


class LongJumpV3Task(SeededStart, LongJumpV2Task):
    name = "long_jump_v3"
    controller = os.path.join(ROOT_BIN, "robolab_long_jump_v3")
    timestep = TIMESTEP
    board_x = CHECK_MARK_V3

    def builder(self):
        if RIGID:
            return HumanoidV2Builder(self.mode, strength=self.strength, wrists=self.wrists)
        return HumanoidV3Builder(self.mode, strength=self.strength, wrists=self.wrists,
                                 stiffness_scale=TENDON_SCALE)

    def reset(self, m, d):
        super().reset(m, d)  # SeededStart: task.seed -> ROBOLAB_LJ_SEED
        settle_fibers(m, d)

    def title(self):
        return "robolab: long jump, v3 anatomy (v2 + elastic Achilles and quadriceps tendons; strength 1.0)"


TASK = LongJumpV3Task
