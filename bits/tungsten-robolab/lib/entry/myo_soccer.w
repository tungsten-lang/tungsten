# robolab controller for the MyoChallenge 2025 soccer penalty kick.

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
use robolab/skills/myo_soccer

Robolab.serve(->(body, params) MyoSoccerSkill.new(body, params))
