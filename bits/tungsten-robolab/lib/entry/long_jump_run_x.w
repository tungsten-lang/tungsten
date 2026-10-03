# robolab controller for the long jump on the labelled beyond-human body's run-up
# (LongJumpRunXSkill, lib/robolab/skills/long_jump_run_x.w: a copy of LongJumpRunSkill on RunGearXSkill).

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
use robolab/tcn
use robolab/skills/run
use robolab/skills/run_ri
use robolab/skills/run_knot
use robolab/skills/run_gear
use robolab/skills/run_gearx
use robolab/skills/long_jump_run_x

Robolab.serve(->(body, params) LongJumpRunXSkill.new(body, params))
