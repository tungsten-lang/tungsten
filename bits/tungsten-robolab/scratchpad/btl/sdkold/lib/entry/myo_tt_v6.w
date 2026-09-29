# robolab controller for MyoChallenge 2025 table tennis (myoArm + myoTorso): round-5 development build (backhand and forehand-depth challengers).

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
