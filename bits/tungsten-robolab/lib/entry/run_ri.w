# robolab controller for the running skill with reciprocal inhibition (run_ri).

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

Robolab.serve(->(body, params) RunRISkill.new(body, params))
