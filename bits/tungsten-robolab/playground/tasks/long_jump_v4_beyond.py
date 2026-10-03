"""long_jump_v4_beyond: the long jump of the LABELLED BEYOND-HUMAN body, UNLIMITED RUN-UP.

The body is playground/profiles/beyond.json (strength x2.4, muscle speed x2.0, tendon stiffness x1.5, activation time
constants x0.8, on the average 1.75 m / 67.5 kg skeleton, the v4 anatomy: ROBOLAB_CALIB=v4, ROBOLAB_PROFILE=beyond,
ROBOLAB_PROFILE_PARTS=strength,speed,tendon,activation). It is an INVENTED stretch, not a human profile, and its
scores are never to be compared with the human-body long-jump trials (long_jump_v4_p95* and the others).

Same scene, rules (World Athletics TR 29-30 as encoded in long_jump_run.py), metrics and seeded starts as
long_jump_v4_p95b, with three labelled differences:
  - the check mark is an unlimited run-up: 150 m by default (the beyond runner needs about 140 m, 19 s, to reach
    10 m/s; ROBOLAB_LJ_APPROACH overrides it);
  - the sand pit is 14 m long (ROBOLAB_LJ_PIT_LEN; the standard 9 m pit ends 9.5 m from the line, a beyond-human jump
    must land in sand);
  - the runner is S4's chain C / D of RunGearXSkill under the jump (LongJumpRunXSkill, bin/robolab_long_jump_run_x).

The profile is set HERE (class attribute) because body_profile.resolve() lets an explicit profile win over the
environment, and LongJumpP95Task hard-codes profile = "p95": the env variable alone would build the P95 body.
"""

import os

from tasks.long_jump import ROOT_BIN
from tasks.long_jump_v4_p95 import LongJumpV4P95Task


class LongJumpV4BeyondTask(LongJumpV4P95Task):
    name = "long_jump_v4_beyond"
    controller = os.path.join(ROOT_BIN, "robolab_long_jump_run_x")
    profile = "beyond"
    profile_parts = "strength,speed,tendon,activation"
    board_x = float(os.environ.get("ROBOLAB_LJ_APPROACH", "150.0"))
    pit_len = float(os.environ.get("ROBOLAB_LJ_PIT_LEN", "14.0"))
    # only sets the rollout length (1.5 s start + run-up + 3.5 s landing and recovery): the runner averages about 7.4 m/s
    # over its first 150 m
    run_speed = 7.0

    def title(self):
        return ("robolab: long jump, labelled beyond-human body, unlimited run-up "
                "(v4 anatomy, strength x2.4, muscle speed x2.0, tendon x1.5, activation x0.8)")


TASK = LongJumpV4BeyondTask
