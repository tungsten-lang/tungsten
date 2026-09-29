# robolab controller for MyoSuite die reorientation (MyoChallenge 2022), round
# 4: MyoDieV4Skill (the round-3 skill plus the wrist-carried closed-loop
# finish, opt-in by `wfin`).

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
use robolab/skills/myo_die
use robolab/skills/myo_die_v3
use robolab/skills/myo_die_v4

Robolab.serve(->(body, params) MyoDieV4Skill.new(body, params))
