"""long_jump_v4_beyond_a: long_jump_v4_beyond (the LABELLED BEYOND-HUMAN body, UNLIMITED RUN-UP) with the check mark 151.025 m,
the mark the one-start take-off program of params/long_jump_beyond_nom1.txt was designed for. The approach of this runner is a
sporadic function of the check mark at the 0.01 m scale (the stride phase at 150 m moves by up to a step), so the mark is part of
the design: the nominal start's penultimate touchdown (left foot, 148.19 m) is 2.83 m from this line, the plant step the ideal
take-off wants. ROBOLAB_LJ_APPROACH does not override it. Never compare its scores with the human-body long-jump trials."""

from tasks.long_jump_v4_beyond import LongJumpV4BeyondTask


class LongJumpV4BeyondATask(LongJumpV4BeyondTask):
    name = "long_jump_v4_beyond_a"
    board_x = 151.025


TASK = LongJumpV4BeyondATask
