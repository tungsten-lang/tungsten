# robolab controller for the long jump on the sprinter's run-up
# (LongJumpRunSkill, lib/robolab/skills/long_jump_run.w: RunGearSkill (RunKnot /
# RunRI, one or more gears) + take-off, flight and landing).

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
use robolab/skills/long_jump_run

Robolab.serve(->(body, params) LongJumpRunSkill.new(body, params))
