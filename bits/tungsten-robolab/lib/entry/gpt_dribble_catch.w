# robolab controller for the basketball dribble skill.

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
use robolab/skills/dribble

use robolab/skills/gpt_temporal
use robolab/skills/gpt_catch_dribble

Robolab.serve(->(body, params) GptCatchDribbleSkill.new(body, params))
