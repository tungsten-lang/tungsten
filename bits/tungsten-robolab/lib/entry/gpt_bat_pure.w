# robolab controller for the baseball bat swing skill.

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
use robolab/skills/bat

use robolab/skills/gpt_temporal
use robolab/skills/gpt_bat

Robolab.serve(->(body, params) GptBatSkill.new(body, params))
