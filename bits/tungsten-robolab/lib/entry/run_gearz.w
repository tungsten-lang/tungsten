
# robolab controller for the running skill with a second gear (run_gearz: run_geary + the sprint-6 opt-in mechanisms).

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
use robolab/skills/run_gearz

Robolab.serve(->(body, params) RunGearZSkill.new(body, params))
