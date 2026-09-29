# robolab controller for the natural run as a quintic knot train (P7): RunNaturalSkill plus knots and a residual TCN.

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
use robolab/skills/run_natural
use robolab/skills/run_knots

Robolab.serve(->(body, params) RunKnotsSkill.new(body, params))
