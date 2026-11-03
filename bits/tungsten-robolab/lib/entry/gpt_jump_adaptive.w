# robolab controller for the search benchmark's standing broad jump (P1).

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
use robolab/skills/search_jump

use robolab/skills/gpt_temporal
use robolab/skills/gpt_jump

use robolab/skills/gpt_adaptive_jump

Robolab.serve(->(body, params) GptAdaptiveJumpSkill.new(body, params))
