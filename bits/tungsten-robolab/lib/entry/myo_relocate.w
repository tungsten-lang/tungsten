# robolab controller for MyoSuite Relocate (MyoChallenge 2023).

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

Robolab.serve(->(body, params) MyoRelocateSkill.new(body, params))
