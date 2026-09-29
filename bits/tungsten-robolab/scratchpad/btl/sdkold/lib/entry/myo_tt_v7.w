# robolab controller for MyoChallenge 2025 table tennis (myoArm + myoTorso): round-6 development build (a working backhand: reachable targets, grip squeeze, timed bursts; stroke power).

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

Robolab.serve(->(body, params) MyoTTV7Skill.new(body, params))
