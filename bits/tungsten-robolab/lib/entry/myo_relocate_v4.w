# robolab controller for MyoSuite Relocate (MyoChallenge 2023), round 4:
# MyoRelocateV4Skill: the round-3 skill (MyoRelocateV3Skill) plus the
# placement latch (drop_in, lead), opt-in.

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
use robolab/skills/myo_relocate_postures_v3
use robolab/skills/myo_relocate_ff
use robolab/skills/myo_relocate_ff_v3
use robolab/skills/myo_relocate
use robolab/skills/myo_relocate_v3
use robolab/skills/myo_relocate_v4

Robolab.serve(->(body, params) MyoRelocateV4Skill.new(body, params))
