# robolab controller for MyoSuite die reorientation (MyoChallenge 2022).

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
use robolab/skills/myo_die

Robolab.serve(->(body, params) MyoDieSkill.new(body, params))
