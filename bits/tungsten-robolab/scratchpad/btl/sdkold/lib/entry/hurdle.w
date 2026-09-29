# robolab controller for the hurdle skill (run a flight of hurdles).

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
use robolab/skills/hurdle

Robolab.serve(->(body, params) HurdleSkill.new(body, params))
