"""long_jump_v4_beyond_a: long_jump_v4_beyond (the LABELLED BEYOND-HUMAN body, UNLIMITED RUN-UP) with the check mark 151.025 m,
the mark the one-start take-off program of params/long_jump_beyond_nom1.txt was designed for. The approach of this runner is a
sporadic function of the check mark at the 0.01 m scale (the stride phase at 150 m moves by up to a step), so the mark is part of
the design: the nominal start's penultimate touchdown (left foot, 148.19 m) is 2.83 m from this line, the plant step the ideal
take-off wants. ROBOLAB_LJ_APPROACH does not override it. Never compare its scores with the human-body long-jump trials."""

from tasks.long_jump_v4_beyond import LongJumpV4BeyondTask

HUMAN_RECORD_M = 8.95  # the men's world record (Powell, 1991)


class LongJumpV4BeyondATask(LongJumpV4BeyondTask):
    name = "long_jump_v4_beyond_a"
    board_x = 151.025

    def metrics(self, m, d, log):
        out = super().metrics(m, d, log)
        # 1.0 for a LEGAL jump past the human record (official_m is 0 for a foul, a somersault, a short landing or a run
        # that never jumps): the per-attempt event behind the best-of-six competition numbers of scratchpad/lj6/bo6.py
        out["record_beaten"] = 1.0 if out.get("official_m", 0.0) > HUMAN_RECORD_M else 0.0
        return out


TASK = LongJumpV4BeyondATask
