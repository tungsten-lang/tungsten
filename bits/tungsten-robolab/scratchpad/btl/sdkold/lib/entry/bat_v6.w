# robolab controller for the baseball bat swing skill, v6: the v5 swing
# (skills/bat.w) plus the opt-in power features of skills/bat_power.w. A
# separate binary so the frozen bat champions are never rebuilt.

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
use robolab/skills/bat_program
use robolab/skills/bat_power

Robolab.serve(->(body, params) BatPowerSkill.new(body, params))
