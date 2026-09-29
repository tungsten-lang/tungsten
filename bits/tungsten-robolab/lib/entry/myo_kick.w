# robolab controller for the MyoChallenge 2025 soccer penalty kick, round 10 (agent P):
# MyoKickSkill (the closed-loop kick: torque-space aim, heading and height terms on the swing; see lib/robolab/skills/myo_kick.w).

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
use robolab/skills/myo_kick

Robolab.serve(->(body, params) MyoKickSkill.new(body, params))
