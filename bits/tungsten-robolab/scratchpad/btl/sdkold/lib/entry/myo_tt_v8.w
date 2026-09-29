# robolab controller for MyoChallenge 2025 table tennis (myoArm + myoTorso): round-7 development build (a learned contact model, side choice, the backhand grasp).

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
use robolab/skills/myo_tt_v7
use robolab/skills/myo_tt_v8

Robolab.serve(->(body, params) MyoTTV8Skill.new(body, params))
