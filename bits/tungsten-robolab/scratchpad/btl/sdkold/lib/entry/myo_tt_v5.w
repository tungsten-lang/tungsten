# robolab controller for MyoChallenge 2025 table tennis (myoArm + myoTorso): round-4 development build (height and depth challengers).

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
use robolab/skills/myo_tt

Robolab.serve(->(body, params) MyoTTSkill.new(body, params))
