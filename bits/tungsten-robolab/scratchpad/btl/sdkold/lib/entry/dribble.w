# robolab controller for the basketball dribble skill.

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
use robolab/skills/dribble

Robolab.serve(->(body, params) DribbleSkill.new(body, params))
