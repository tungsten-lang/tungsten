# robolab controller for the touch-only sprint (one touchdown keyframe, phase bursts).

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
use robolab/skills/sprint_touch

Robolab.serve(->(body, params) SprintTouchSkill.new(body, params))
