"""Long jump on the v2 anatomy: human-calibrated muscle speeds, biarticular
muscles (rectus femoris, hamstrings, gastrocnemius) and toe (MTP) joints, at
the shared strength 1.0 with no speed override (HumanoidV2Builder as is).

Same scene, sensors, metrics and scoring as the long_jump task (planar root:
the body stays in the sagittal plane); the toe segments count as part of the
feet for contacts, marks and take-off. The skill is the same LongJumpSkill;
its v2-only features (biarticular and toe drives, toe-off) are parameters
that the v1 body simply does not have muscles for.

Environment overrides as for long_jump (ROBOLAB_LJ_APPROACH sets this task's
run-up too; the default is the v2 athlete's check mark).
"""

import os

from body import HumanoidV2Builder
from tasks.long_jump import LongJumpTask, ROOT_BIN

APPROACH_V2 = float(os.environ.get("ROBOLAB_LJ_APPROACH", "12.9"))


class LongJumpV2Task(LongJumpTask):
    name = "long_jump_v2"
    controller = os.path.join(ROOT_BIN, "robolab_long_jump_v2")
    strength = 1.0
    vmax = "per joint (V2_OMEGA: hip 15, knee 25, ankle 20, toe 15 rad/s unloaded)"
    board_x = APPROACH_V2

    def builder(self):
        return HumanoidV2Builder(self.mode, strength=self.strength, wrists=self.wrists)

    def title(self):
        return "robolab: long jump, v2 anatomy (calibrated speeds, biarticulars, toes; strength 1.0)"


TASK = LongJumpV2Task
