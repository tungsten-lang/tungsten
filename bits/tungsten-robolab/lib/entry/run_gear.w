# robolab controller for the running skill with a second gear (run_gear: run_knot + a stride rebuilt from g2_ parameters above a speed).

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

Robolab.serve(->(body, params) RunGearSkill.new(body, params))
