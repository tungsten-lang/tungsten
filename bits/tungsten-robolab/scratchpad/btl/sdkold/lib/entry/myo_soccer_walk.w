# robolab controller for the MyoChallenge 2025 soccer body walking: the
# chase-tag walker on the soccer body (MyoSoccerWalkSkill), the phase-2
# approach.

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
use robolab/skills/myo_soccer
use robolab/skills/myo_soccer_walk

Robolab.serve(->(body, params) MyoSoccerWalkSkill.new(body, params))
