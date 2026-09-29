# robolab controller for the MyoChallenge 2025 soccer penalty kick, round 3:
# MyoSoccerV3Skill (single-leg balance, inside-of-the-foot kick, approach).

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
use robolab/skills/myo_soccer_v3

Robolab.serve(->(body, params) MyoSoccerV3Skill.new(body, params))
