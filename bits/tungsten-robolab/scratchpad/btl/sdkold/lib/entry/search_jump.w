# robolab controller for the search benchmark's standing broad jump (P1).

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
use robolab/tcn
use robolab/skills/search_jump

Robolab.serve(->(body, params) SearchJumpSkill.new(body, params))
