# robolab controller for the search benchmark's MyoSuite balance skill (P2).

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
use robolab/skills/search_balance

Robolab.serve(->(body, params) SearchBalanceSkill.new(body, params))
