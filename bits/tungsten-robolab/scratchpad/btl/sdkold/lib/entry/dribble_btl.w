# robolab controller for the between-the-legs dribble (skills/dribble_btl.w on DribbleV3Skill).

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
use robolab/skills/dribble_v3
use robolab/skills/dribble_btl

Robolab.serve(->(body, params) DribbleBtlSkill.new(body, params))
