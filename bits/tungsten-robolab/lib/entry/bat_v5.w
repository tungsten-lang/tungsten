# robolab controller for the baseball bat swing skill (v5 build: the bat.w skill with the 2026-09-27 flow options; a separate binary so the frozen bat champions are never rebuilt).

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

Robolab.serve(->(body, params) BatSkill.new(body, params))
