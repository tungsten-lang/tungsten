# robolab controller for MyoSuite bimanual handover (MyoChallenge 2024).

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
use robolab/skills/myo_bimanual_prosthesis
use robolab/skills/myo_bimanual

Robolab.serve(->(body, params) MyoBimanualSkill.new(body, params))
