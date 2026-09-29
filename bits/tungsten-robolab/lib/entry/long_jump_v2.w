# robolab controller for the long jump skill on the v2 anatomy (same skill;
# a separate binary so v1 and v2 practice can run side by side).

use robolab/easing
use robolab/body
use robolab/contraction
use robolab/sensors
use robolab/latch
use robolab/chunk
use robolab/reflex
use robolab/controller
use robolab/link
use robolab/skill
use robolab/skills/long_jump

Robolab.serve(->(body, params) LongJumpSkill.new(body, params))
