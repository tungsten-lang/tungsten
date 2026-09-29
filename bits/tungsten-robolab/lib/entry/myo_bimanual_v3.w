# robolab controller for MyoSuite bimanual handover (MyoChallenge 2024), round
# 3: MyoBimanualV3Skill (static feed-forward, joint-space PD, pronation-capped
# posture table; each opt-in).

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

Robolab.serve(->(body, params) MyoBimanualV3Skill.new(body, params))
