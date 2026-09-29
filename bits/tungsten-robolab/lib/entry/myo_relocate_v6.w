# robolab controller for MyoSuite Relocate (MyoChallenge 2023), round 6:
# MyoRelocateV6Skill: the round-5 skill (MyoRelocateV5Skill) plus
# position-indexed settings for the evaluation env's wider object range, a
# reactive grip and a stalled-reach escape, each opt-in.

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
use robolab/skills/myo_relocate_v6

Robolab.serve(->(body, params) MyoRelocateV6Skill.new(body, params))
