# robolab controller for the long jump skill.

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
