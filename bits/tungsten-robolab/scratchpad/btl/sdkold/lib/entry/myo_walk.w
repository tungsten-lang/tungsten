# robolab controller for MyoSuite 3D standing balance and walking.

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

Robolab.serve(->(body, params) MyoWalkSkill.new(body, params))
