# robolab controller for the basketball dribble skill, v3 (arms-only, elbow-driven, V crossovers, fingered hands).

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

Robolab.serve(->(body, params) DribbleV3Skill.new(body, params))
