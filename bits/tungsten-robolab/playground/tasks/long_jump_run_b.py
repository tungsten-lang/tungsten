"""long_jump_run (average v3 body) with the check mark learned across
attempts (playground/long_jump_run_checkmark.py: the run-up shortened until
the take-off foot's front lands ~0.1 m behind the line on the training
starts): 35.27 m from the start to the foul line (long_jump_run: 35.6 m).
Same body, scene, rules and metrics. ROBOLAB_LJ_APPROACH overrides it."""

import os

from tasks.long_jump_run import LongJumpRunTask


class LongJumpRunBTask(LongJumpRunTask):
    name = "long_jump_run_b"
    board_x = float(os.environ.get("ROBOLAB_LJ_APPROACH", "35.27"))


TASK = LongJumpRunBTask
