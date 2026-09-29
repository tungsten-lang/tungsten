# robolab controller for the stand bring-up skill.

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
use robolab/skills/stand

Robolab.serve(->(body, params) StandSkill.new(body, params))
