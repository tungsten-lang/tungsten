# robolab controller for the long jump on the labelled beyond-human body's fall-reduced run-up
# (LongJumpRunYSkill, lib/robolab/skills/long_jump_run_y.w: a copy of LongJumpRunSkill on RunGearYSkill).

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
use robolab/skills/run_geary
use robolab/skills/long_jump_run_y

Robolab.serve(->(body, params) LongJumpRunYSkill.new(body, params))
