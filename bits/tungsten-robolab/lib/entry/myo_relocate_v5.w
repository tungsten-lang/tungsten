# robolab controller for MyoSuite Relocate (MyoChallenge 2023), round 5:
# MyoRelocateV5Skill: the round-4 skill (MyoRelocateV4Skill) plus the settle
# latch, the seen-object aim, the round-5 posture table and the controlled
# transport, each opt-in.

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
use robolab/skills/myo_relocate_postures_v5
use robolab/skills/myo_relocate_ff
use robolab/skills/myo_relocate_ff_v3
use robolab/skills/myo_relocate_ff_v5
use robolab/skills/myo_relocate
use robolab/skills/myo_relocate_v3
use robolab/skills/myo_relocate_v4
use robolab/skills/myo_relocate_v5

Robolab.serve(->(body, params) MyoRelocateV5Skill.new(body, params))
