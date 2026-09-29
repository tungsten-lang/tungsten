# robolab controller for the MyoChallenge 2025 soccer penalty kick, round 4:
# MyoSoccerV4Skill (turn by stepping: twist-limited heading hold, swing feet
# turned in the air, angled approaches).

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
use robolab/skills/myo_soccer_v4

Robolab.serve(->(body, params) MyoSoccerV4Skill.new(body, params))
