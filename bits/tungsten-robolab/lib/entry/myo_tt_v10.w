# robolab controller for MyoChallenge 2025 table tennis (myoArm + myoTorso): round-9 development build (live tracking: thresholds from the muscles' live moment arms).

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
use robolab/skills/myo_tt_v9
use robolab/skills/myo_tt_v10

Robolab.serve(->(body, params) MyoTTV10Skill.new(body, params))
