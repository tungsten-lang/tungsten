# robolab controller for the running skill with reciprocal inhibition and the distilled knot stance (run_knot).

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

Robolab.serve(->(body, params) RunKnotSkill.new(body, params))
