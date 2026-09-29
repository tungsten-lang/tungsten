# robolab controller for MyoSuite MyoChallenge chase-tag (walks with MyoWalk).

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
use robolab/skills/myo_walk
use robolab/skills/myo_chase

Robolab.serve(->(body, params) MyoChaseSkill.new(body, params))
