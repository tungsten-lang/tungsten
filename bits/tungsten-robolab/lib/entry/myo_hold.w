# robolab controller for MyoSuite bring-up (hold posture).

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
use robolab/skills/myo_hold

Robolab.serve(->(body, params) MyoHoldSkill.new(body, params))
