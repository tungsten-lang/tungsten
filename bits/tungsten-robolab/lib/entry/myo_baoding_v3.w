# robolab controller for MyoSuite Baoding balls (MyoChallenge 2022), round 3:
# MyoBaodingV3Skill (rotating field on the measured pair angle; opt-in).

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
use robolab/skills/myo_baoding_v3

Robolab.serve(->(body, params) MyoBaodingV3Skill.new(body, params))
