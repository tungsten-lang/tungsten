# robolab controller for MyoSuite die reorientation (MyoChallenge 2022), round
# 3: MyoDieV3Skill (palm-roll primitives, greedy choice by measured effect;
# each opt-in).

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

Robolab.serve(->(body, params) MyoDieV3Skill.new(body, params))
