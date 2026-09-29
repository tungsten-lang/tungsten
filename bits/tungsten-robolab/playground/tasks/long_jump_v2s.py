"""long_jump_v2 with seeded starts, for multi-start trials and robust practice.

Identical to long_jump_v2 (v2 body, 2 ms physics, run-up 12.9 m, the same
controller build) except:
  - `task.seed` (set by search.py --seeds and arena.py) perturbs the standing
    start exactly as ROBOLAB_LJ_SEED does (runway position +-0.15 m, leg joints
    0-0.04 rad); None or 0 keeps the ROBOLAB_LJ_SEED the process started with
    (unset: the nominal start), so seed 0 is the long_jump_v2 trial's start;
  - a run that never lands a jump reports official_m 0.0 (no mark), so a
    multi-start trial averages distances rather than failing the metric.
"""

import os

from tasks.long_jump_v2 import LongJumpV2Task

ENV_SEED = os.environ.get("ROBOLAB_LJ_SEED")


class SeededStart:
    """Mixin for LongJumpTask subclasses: task.seed -> ROBOLAB_LJ_SEED, and
    official_m 0.0 for a run without a landed jump."""

    seed = None

    def reset(self, m, d):
        if self.seed:
            os.environ["ROBOLAB_LJ_SEED"] = str(int(self.seed))
        elif ENV_SEED is None:
            os.environ.pop("ROBOLAB_LJ_SEED", None)  # a worker's earlier seeded rollout must not leak
        else:
            os.environ["ROBOLAB_LJ_SEED"] = ENV_SEED
        super().reset(m, d)

    def metrics(self, m, d, log):
        out = super().metrics(m, d, log)
        out.setdefault("official_m", 0.0)
        return out


class LongJumpV2STask(SeededStart, LongJumpV2Task):
    name = "long_jump_v2s"
    controller = LongJumpV2Task.controller


TASK = LongJumpV2STask
