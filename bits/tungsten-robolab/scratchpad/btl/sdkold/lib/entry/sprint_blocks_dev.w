# robolab controller for the sprint from starting blocks: development build (bin/robolab_sprint_blocks stays the build searches and the arena use).

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
use robolab/skills/sprint_ref
use robolab/skills/sprint_blocks

Robolab.serve(->(body, params) SprintBlocksSkill.new(body, params))
