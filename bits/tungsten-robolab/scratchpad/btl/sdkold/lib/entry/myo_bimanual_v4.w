# robolab controller for MyoSuite bimanual handover (MyoChallenge 2024), round
# 4: MyoBimanualV4Skill (the round-3 skill plus a closed-loop, arrival-latched
# prosthesis handover; opt-in).

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
use robolab/skills/myo_relocate_postures
use robolab/skills/myo_relocate
use robolab/skills/myo_bimanual_postures
use robolab/skills/myo_bimanual_postures_v3
use robolab/skills/myo_bimanual_ff
use robolab/skills/myo_bimanual_ff_v3
use robolab/skills/myo_bimanual_prosthesis
use robolab/skills/myo_bimanual
use robolab/skills/myo_bimanual_v3
use robolab/skills/myo_bimanual_v4

Robolab.serve(->(body, params) MyoBimanualV4Skill.new(body, params))
