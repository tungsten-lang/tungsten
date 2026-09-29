# robolab controller for the long jump with opt-in COM-state take-off and
# landing latches (LongJumpComSkill, lib/robolab/skills/long_jump_com.w).

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
use robolab/skills/long_jump_com

Robolab.serve(->(body, params) LongJumpComSkill.new(body, params))
