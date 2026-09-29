# robolab controller for MyoSuite Relocate (MyoChallenge 2023), round 3:
# MyoRelocateV3Skill (static inverse-dynamics feed-forward, joint-space PD,
# the pronation-capped posture table and the wrap grasp, each opt-in).

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

Robolab.serve(->(body, params) MyoRelocateV3Skill.new(body, params))
