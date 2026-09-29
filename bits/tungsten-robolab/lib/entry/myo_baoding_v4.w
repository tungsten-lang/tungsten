# robolab controller for MyoSuite Baoding (MyoChallenge 2022), round 4:
# MyoBaodingV4Skill (the palm-tilt skill plus a push/relax finger gait whose
# pushes are chosen by the pair's measured angle, opt-in by `pg`).

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
use robolab/skills/myo_baoding_tilt
use robolab/skills/myo_baoding_v4

Robolab.serve(->(body, params) MyoBaodingV4Skill.new(body, params))
