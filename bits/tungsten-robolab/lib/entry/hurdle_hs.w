# robolab controller for the high-school 110 m hurdles skill (HurdleHSSkill,
# on RunSkill's gait; see lib/robolab/skills/hurdle_hs.w).

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
use robolab/skills/run
use robolab/skills/hurdle_hs

Robolab.serve(->(body, params) HurdleHSSkill.new(body, params))
