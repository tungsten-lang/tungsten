# robolab controller for the natural (keyframe) running skill.

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
use robolab/skills/run_natural

Robolab.serve(->(body, params) RunNaturalSkill.new(body, params))
