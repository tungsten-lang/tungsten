# robolab controller for MyoSuite Baoding balls (MyoChallenge 2022).

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
use robolab/skills/myo_baoding

Robolab.serve(->(body, params) MyoBaodingSkill.new(body, params))
