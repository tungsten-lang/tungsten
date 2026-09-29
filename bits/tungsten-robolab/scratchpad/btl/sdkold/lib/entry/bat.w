# robolab controller for the baseball bat swing skill.

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
use robolab/skills/bat

Robolab.serve(->(body, params) BatSkill.new(body, params))
